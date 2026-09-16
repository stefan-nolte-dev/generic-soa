unit AppCallerToken;

{$I mormot.defines.inc}

{ Who is calling - the one place that reads the HTTP request.

  The token comes out of the Authorization header here and nowhere else, and
  what leaves this unit is a TSqlCaller: a plain record of user, name and
  group mask. Everything below sees only that, so the rights check can be
  tested by filling a record instead of by faking a session.

  A token here is a JWT, signed and verified with HMAC-SHA256 by mORMot's
  own TJwtHS256: signature, issuer and expiry are its business, and what this
  unit does with the result is read four claims out of it.

  The secret is a GUID drawn at startup and kept in memory. Nothing to check
  in, nothing to leak from a config file - and every token dies with the
  process, which for a sample is the right trade: a restart is the crudest
  possible revocation, and it is the only one this needs.

  The same arrangement as the auth service this sample belongs beside, which
  also signs HS256 with a startup GUID and 300 minutes. Where that one is a
  separate process, this one issues for itself; moving to "somebody else
  issues, we only verify" is a different constructor here and nothing else,
  because everything below reads the TSqlCaller and never the token. }

interface

uses
  SysUtils,
  mormot.core.base,
  mormot.core.log,      // a refused token is worth a line
  mormot.core.os,       // for UnixTimeUtc, to say how long a token has left
  mormot.core.text,
  mormot.core.unicode,  // for IdemPChar
  mormot.core.variants, // the claims come back as a TDocVariant
  mormot.crypt.jwt,     // TJwtHS256 - signing and verifying are not ours
  mormot.rest.server,   // for the request behind the current call
  SqlAuthTypes,         // TAuthPayload: what a token says, for all three
  DomSqlServices;

const
  /// who signed it, in the "iss" claim
  // - checked on the way back in, so a token from another service of this
  // family is not silently taken for one of ours
  TOKEN_ISSUER = 'soa_sql_templates';

  /// how long a token is good for
  // - 300 minutes, as in the auth service next door: long enough to work a
  // session, short enough that a blocked account is out within the hour
  TOKEN_MINUTES = 300;

/// build the caller of the SOA method running right now
function CurrentCaller: TSqlCaller;

/// the bearer token of the call running right now, or ''
// - for WhoAmI, which has to say something about the token itself rather
// than about the caller it made
function CurrentToken: TSessionToken;

/// signature, issuer, expiry - and the four claims out
// - Why says what was wrong, for the log; the caller is told no more than
// that the call was refused, because which half failed is not their business
function VerifyToken(const Token: TSessionToken; out Payload: TAuthPayload;
  out Why: RawUtf8): boolean;

/// the token this payload gets, signed and dated
// - what Login hands back, and the only place a token is made
function IssueToken(const Payload: TAuthPayload): TSessionToken;

/// how many seconds this token still has, or 0 when it is done
// - for WhoAmI, so a client can say it rather than find out by being refused
function TokenSecondsLeft(const Token: TSessionToken): integer;

/// draw the signing secret and build the signer
// - called once at startup; the secret is a GUID and never leaves memory
procedure InitTokens;

/// drop the signer, and with it every token it ever signed
procedure DoneTokens;

var
  /// whether a call without a usable token is refused
  // - false, the default for this sample: it runs without authentication, so
  // every caller is let through as group 1
  // - true: no token, no call - and TokenToCaller decides what a token is
  RequireToken: boolean = false;

  /// which groups an untokened caller may read with while RequireToken is
  /// false
  // - group 1 only, so a template that names any other mask still refuses
  AnonymousReads: Int64 = 1;

  /// and write with
  AnonymousWrites: Int64 = 1;

  /// which UserID an untokened caller is given while RequireToken is false
  // - 0 as shipped, and no row carries a 0: a template with CallerScope set
  // returns nothing at all until something names the caller
  // - set it to a customer id to watch caller scoping work before there is a
  // token to carry one. A screw for trying it out, not authentication: it
  // says every anonymous caller is that one user
  AnonymousUserID: integer = 0;

implementation

var
  /// signs and verifies - one instance, and mORMot says it is thread-safe
  Signer: TJwtHS256;

procedure InitTokens;
var
  guid: TGuid;
begin
  if Signer <> nil then
    exit;
  { a secret nobody typed and nobody stored: it is drawn here and lives in
    this process only. The cost is that a restart invalidates every token,
    which is the behaviour this sample wants anyway }
  CreateGuid(guid);
  Signer := TJwtHS256.Create(GuidToRawUtf8(guid), {pbkdf2rounds=}0,
    [jrcIssuer, jrcExpirationTime], [], TOKEN_MINUTES);
end;

procedure DoneTokens;
begin
  FreeAndNil(Signer);
end;

function IssueToken(const Payload: TAuthPayload): TSessionToken;
begin
  result := '';
  if Signer = nil then
    exit; // nobody called InitTokens: no token rather than an unsigned one
  { the claim names live in SqlAuthTypes because the client reads some of
    them too - and short, because they travel on every single call }
  result := Signer.Compute([
    AUTHCLAIM_USERID, Payload.UserID,
    AUTHCLAIM_NAME,   Payload.UserName,
    AUTHCLAIM_READS,  Payload.Reads,
    AUTHCLAIM_WRITES, Payload.Writes], TOKEN_ISSUER);
end;

{ read the four claims out of a token mORMot has already accepted }
procedure PayloadFrom(var Jwt: TJwtContent; out Payload: TAuthPayload);
var
  value: variant;
begin
  Payload := default(TAuthPayload);
  Payload.UserID := Jwt.data.I[AUTHCLAIM_USERID];
  Payload.UserName := Jwt.data.U[AUTHCLAIM_NAME];
  if Jwt.data.GetValueByPath(AUTHCLAIM_READS, value) then
    Payload.Reads := VariantToInt64Def(value, 0);
  if Jwt.data.GetValueByPath(AUTHCLAIM_WRITES, value) then
    Payload.Writes := VariantToInt64Def(value, 0);
end;

function VerifyToken(const Token: TSessionToken; out Payload: TAuthPayload;
  out Why: RawUtf8): boolean;
var
  jwt: TJwtContent;
begin
  Payload := default(TAuthPayload);
  Why := '';
  result := false;
  if Token = '' then
  begin
    Why := 'no token';
    exit;
  end;
  if Signer = nil then
  begin
    Why := 'no signer - InitTokens was never called';
    exit;
  end;
  { signature, issuer and expiry in one call, and none of them ours to get
    subtly wrong: a hand written expiry check that reads the claim and
    forgets to compare it looks exactly like one that works }
  Signer.Verify(Token, jwt);
  if jwt.result <> jwtValid then
  begin
    Why := RawUtf8(ToText(jwt.result)^);
    exit;
  end;
  if jwt.reg[jrcIssuer] <> TOKEN_ISSUER then
  begin
    Why := FormatUtf8('issued by "%", not by us', [jwt.reg[jrcIssuer]]);
    exit;
  end;
  PayloadFrom(jwt, Payload);
  if (Payload.Reads = 0) and
     (Payload.Writes = 0) then
  begin
    { a payload naming no group can do nothing anyway once StrictRights is on,
      and letting it through would look like a right rather than an omission }
    Why := 'the payload names no group, for reading or for writing';
    exit;
  end;
  result := true;
end;

function TokenSecondsLeft(const Token: TSessionToken): integer;
var
  jwt: TJwtContent;
  expires: Int64;
begin
  result := 0;
  if (Token = '') or
     (Signer = nil) then
    exit;
  Signer.Verify(Token, jwt);
  if jwt.result <> jwtValid then
    exit;
  { the expiry is a registered claim, so mORMot keeps it in reg[] - and it
    already refused the token above if it had passed }
  expires := GetInt64(pointer(jwt.reg[jrcExpirationTime]));
  if expires > 0 then
    result := expires - UnixTimeUtc;
  if result < 0 then
    result := 0;
end;

/// what a token says about its bearer, as the layers below want it
// - the record is filled from the payload and from nowhere else: no default
// group, no fallback user. What the token does not say, the caller does not
// have
function TokenToCaller(const Token: TSessionToken;
  out Caller: TSqlCaller): boolean;
var
  payload: TAuthPayload;
  why: RawUtf8;
begin
  Caller := default(TSqlCaller);
  result := VerifyToken(Token, payload, why);
  if not result then
  begin
    if Token <> '' then
      TSynLog.Add.Log(sllWarning, 'TokenToCaller: %', [why]);
    exit;
  end;
  Caller.Authenticated := true;
  Caller.UserID := payload.UserID;
  Caller.UserName := payload.UserName;
  Caller.Reads := payload.Reads;
  Caller.Writes := payload.Writes;
end;

function BearerFromHeader: RawUtf8;
var
  ctx: PServiceRunningContext;
  head: RawUtf8;
begin
  result := '';
  ctx := ServiceRunningContext;
  if (ctx = nil) or
     (ctx^.Request = nil) then
    exit;
  head := ctx^.Request.InHeader['authorization'];
  if IdemPChar(pointer(head), 'BEARER ') then
    result := copy(head, 8, maxInt);
end;

function CurrentToken: TSessionToken;
begin
  result := BearerFromHeader;
end;

function CurrentCaller: TSqlCaller;
var
  ctx: PServiceRunningContext;
begin
  if TokenToCaller(BearerFromHeader, result) then
    exit;
  if RequireToken then
  begin
    result := default(TSqlCaller); // Authenticated stays false: refused above
    exit;
  end;
  { no token, and none demanded. mORMot's own session is used when there is
    one, so switching the sample to authenticated REST needs no change here }
  result := default(TSqlCaller);
  result.Authenticated := true;
  result.Reads := AnonymousReads;
  result.Writes := AnonymousWrites;
  result.UserID := AnonymousUserID;
  ctx := ServiceRunningContext;
  if (ctx <> nil) and
     (ctx^.Request <> nil) and
     (ctx^.Request.SessionGroup > 0) and
     (ctx^.Request.SessionGroup <= 63) then
  begin
    result.UserID := ctx^.Request.SessionUser;
    result.UserName := ctx^.Request.SessionUserName;
    result.Reads := Int64(1) shl (ctx^.Request.SessionGroup - 1);
    result.Writes := result.Reads; // one group per user is all a session has
  end;
end;

end.
