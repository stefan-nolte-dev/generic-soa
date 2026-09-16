unit SqlAuthTypes;

{$I mormot.defines.inc}

{ What a token says, and what a token is - for all three programs.

  In common, next to SqlProfiles and SqlStatus, because server, client and
  editor have to agree on it: the server issues, the two others carry, and a
  type that lived on one side only would eventually mean two things.

  What is NOT here: how a token is signed, and how it is verified. That is
  the server's business and stays in the application layer - the client is
  handed a string, and what it holds is opaque to it by design.

  The shape follows the payload of the auth service this sample belongs
  beside: an identity and two masks. Two and not one, because the templates
  have carried ReadGroups and WriteGroups from the start, and a caller with
  one mask for both was the simplification that made that half useless. }

interface

uses
  mormot.core.base;

type
  /// what a client sends back on every call, in the Authorization header
  // - a distinct type, so a parameter that takes one cannot be handed any
  // other string by accident
  TSessionToken = type RawUtf8;

  /// what the token carries, and the only thing the server reads out of it
  // - Reads and Writes are matched against TSqlRec.ReadGroups and
  // TSqlRec.WriteGroups: bit 0 is group 1, at most 64 groups
  // - a payload that names neither is refused: nobody is nobody, and letting
  // it through would look like a right rather than an omission
  TAuthPayload = record
    /// the bearer - what CallerScope binds where a template asks for it
    UserID: integer;
    /// the bearer's name, for the log and for the status line
    UserName: RawUtf8;
    /// bitmask of the groups this bearer may read with
    Reads: Int64;
    /// bitmask of the groups this bearer may write with
    Writes: Int64;
  end;

const
  /// the claim names inside the token
  // - short, because they travel on every single call
  AUTHCLAIM_USERID = 'uid';
  AUTHCLAIM_NAME   = 'name';
  AUTHCLAIM_READS  = 'rd';
  AUTHCLAIM_WRITES = 'wr';

implementation

end.
