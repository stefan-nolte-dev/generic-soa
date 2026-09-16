unit SqlStatus;

{$I mormot.defines.inc}

{ What a call came back as - a value, not an exception.

  Every method of IAppSqlTool answers with one of these, so a caller can tell
  "no such key" from "no rows" from "not allowed" without catching anything. }

interface

uses
  mormot.core.base;

type
  /// what came of a GetJsonFromAction / WriteDataForAction call
  TSqlStatus = (
    /// the statement ran and produced rows, or wrote at least one row
    sqlOk,
    /// the action key was empty
    sqlEmptyKey,
    /// the action key is not registered on this server
    sqlUnknownKey,
    /// the caller is authenticated, and this action key is not for them
    // - their Reads or Writes mask does not meet the template's; see
    // TDomSqlTool.CanExecute for what an unset mask means, which is one flag
    // and not a decision per key
    // - not the same thing as sqlNeedsLogin, and the difference is what lets
    // a client tell "log in again" from "this is not yours"
    sqlNotAllowed,
    /// the select ran without error but matched no row
    sqlNoRows,
    /// the insert, update or delete ran without error but changed no row
    sqlNothingWritten,
    /// the statement itself failed - broken SQL, wrong parameter count
    // - the reason is written to the server log, not returned: it belongs to
    // whoever maintains the templates, not to the caller
    sqlFailed,
    /// the values sent do not match what the template declares
    // - appended, so the ordinals of everything above are unchanged on the wire
    sqlBadParams,
    /// nobody is calling: no token, an expired one, or one that is not valid
    // - the client's cue to show its login window and try once more, which
    // it could not do while this was answered as sqlNotAllowed
    // - appended for the same reason as the one above it
    sqlNeedsLogin);

/// 'sqlOk', 'sqlUnknownKey', ... for logs and messages
function ToText(Status: TSqlStatus): RawUtf8;

/// true for sqlOk - reads better than "= sqlOk" at a call site
function Succeeded(Status: TSqlStatus): boolean;
  {$ifdef HASINLINE}inline;{$endif}

implementation

uses
  mormot.core.rtti;

function ToText(Status: TSqlStatus): RawUtf8;
begin
  ShortStringToAnsi7String(
    GetEnumName(TypeInfo(TSqlStatus), ord(Status))^, result);
end;

function Succeeded(Status: TSqlStatus): boolean;
begin
  result := Status = sqlOk;
end;

end.
