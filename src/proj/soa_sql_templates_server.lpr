program soa_sql_templates_server;

{$I mormot.defines.inc}

{$ifdef OSWINDOWS}
  {$apptype console}
{$endif OSWINDOWS}

uses
  {$I mormot.uses.inc}
  SysUtils,
  mormot.core.base,
  mormot.core.os,
  mormot.core.text,
  mormot.core.unicode,
  mormot.db.raw.sqlite3,
  mormot.db.raw.sqlite3.static,
  SqlStatus,
  SqlParamTypes,
  SqlTemplateTypes,
  SqlTemplatesFromDb,
  InfraSqlImplementation, InfraSqlServices,
  DomSqlServices, DomSqlImplementation, // StrictRights lives with the check
  AppSqlServices, AppCallerToken,
  AppSqlImplementation,
  SqlServerConn,
  SqlProfiles,
  ServSqlTemplates;

{ One profile per run: a service talks to one database, and the templates of
  that database are in one file. Without an argument it is the demo. }
function IsCallerArgument(const Arg: RawUtf8): boolean;
begin
  result := IdemPChar(pointer(Arg), 'CALLER=');
end;

{ the switches, so none of them can be mistaken for a profile name }
function IsSwitch(const Arg: RawUtf8): boolean;
begin
  result := IsCallerArgument(Arg) or
            IdemPropNameU(Arg, 'token') or
            IdemPropNameU(Arg, 'strict');
end;

function HasArgument(const Name: RawUtf8): boolean;
var
  i: integer;
begin
  for i := 1 to ParamCount do
    if IdemPropNameU(StringToUtf8(ParamStr(i)), Name) then
      exit(true);
  result := false;
end;

function WantedProfile: RawUtf8;
var
  i: integer;
  arrs: array of RawUTF8;
  s: RawUtf8;
begin
  { the profile is the first argument that is not a switch, so they can be
    given in any order and none is mistaken for the other }
  s := ParamStr(0);
  for i := 1 to ParamCount do
  begin
    result := StringToUtf8(ParamStr(i));
    if not IsSwitch(result) then
      exit;
  end;
  result := PROFILE_DEMO;
end;

{ A second argument, caller=<id>, hands every untokened caller that UserID.
  It exists to make caller scoping visible while the token is still a stub:
  the server binds this where a real token's bearer would be bound. Off
  without the argument, and a scoped template then matches nothing. }
procedure ApplyCallerArgument;
var
  i: integer;
  arg: RawUtf8;
begin
  arg := '';
  for i := 1 to ParamCount do
    if IsCallerArgument(StringToUtf8(ParamStr(i))) then
      arg := StringToUtf8(ParamStr(i));
  if arg = '' then
    exit;
  AnonymousUserID := GetInteger(pointer(arg) + 7);
  TextColor(ccBrown);
  writeln('Every caller without a token is UserID ', AnonymousUserID,
    ' - for trying caller scoping out, not authentication.');
  TextColor(ccLightGray);
end;

{ The two switches that turn the sample from "shows how rights would work"
  into "refuses without them". Off by default, because a machbarkeitsnachweis
  that cannot be started without a token is a poor one - and on, they are what
  a deployment runs with. }
procedure ApplyRightsArguments;
begin
  StrictRights := HasArgument('strict');
  RequireToken := HasArgument('token');
  if StrictRights then
  begin
    TextColor(ccBrown);
    { English and without umlauts, like the switch above it: what a console
      makes of a source literal depends on its code page, and a startup
      banner is the worst place to find that out }
    writeln('strict: an unset rights mask now refuses. A template naming');
    writeln('neither ReadGroups nor WriteGroups answers sqlNotAllowed.');
    TextColor(ccLightGray);
  end;
  { what a login looks like is printed by StartServer, which is where the
    port is known }
end;

begin
  try
    ApplyCallerArgument;
    ApplyRightsArguments;
    StartServer(WantedProfile);
    try
      ConsoleWaitForEnterKey;
    finally
      StopServer;
    end;
  except
    { a startup that cannot work because something around it is not set up is
      not a crash to report - it is an instruction to follow, so it is printed
      as one, without a stack and without the word "fatal" }
    on E: ESqlTemplate do
    begin
      TextColor(ccLightRed);
      writeln(#13#10, E.Message);
      TextColor(ccLightGray);
      ExitCode := 1;
    end;
    on E: Exception do
    begin
      ConsoleShowFatalException(E);
      ExitCode := 1;
    end;
  end;
end.
