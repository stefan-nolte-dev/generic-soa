unit ClientTests;

{$mode objfpc}{$H+}

{ The proof of concept, written against a TStrings so it does not care whether
  the output lands in a console, a memo or a log file.

  What it shows: rows arrive as a Pascal array of records with ordinary typed
  field access, and the code that turns the server's JSON into that array is
  the SAME for every action key and every shape.

    ParseDynArray(<key>, <bounds>, <array>, TypeInfo(<array type>))

  Read it with one question in mind: how much of this would have to change if
  the server offered fifty statements instead of fifteen? The records, and
  nothing else. }

interface

uses
  SysUtils,
  Classes,
  mormot.core.base,
  mormot.core.text,
  mormot.core.variants,
  SqlStatus,
  AppSqlClient,
  ClientDtos,
  WriteDtos,
  u_client_parsing;

/// every registered action, in order
procedure RunAllActions(Log: TStrings);
/// the error path: action keys the server cannot serve
// - no longer raises anything, so this can be part of an ordinary run
procedure RunUnknownAction(Log: TStrings);

implementation

function U(const Text: RawUtf8): string;
begin
  { an LCL string is UTF-8 and so is RawUtf8, so the right conversion here is
    none. Utf8ToString() would be wrong twice over: without
    mormot.core.unicode in scope it resolves to the RTL's, which returns a
    UnicodeString; with it, it converts into the system codepage. }
  result := Text;
end;

procedure Head(Log: TStrings; const Title: string);
begin
  if Log.Count > 0 then
    Log.Add('');
  Log.Add('== ' + Title);
end;

procedure ShowStatus(Log: TStrings; Status: TSqlStatus);
begin
  Log.Add('  [' + U(ToText(Status)) + ']');
end;

procedure ShowCustomers(Log: TStrings; const Customers: TDtoCustomerArray);
var
  i: PtrInt;
begin
  if Customers = nil then
    exit;
  for i := 0 to high(Customers) do
    // typed access, on records the server never heard of
    Log.Add(Format('  %3d  %-24s %s',
      [Customers[i].ID, U(Customers[i].Name), U(Customers[i].City)]));
end;

procedure Selects(Log: TStrings);
var
  Customers: TDtoCustomerArray;
  Turnover: TDtoTurnoverArray;
  Invoices: TDtoInvoiceArray;
  status: TSqlStatus;
  i: PtrInt;
begin
  Head(Log, 'GetAllCustomers - no parameter  ->  TDtoCustomerArray');
  Customers := nil;
  status := ParseDynArray('GetAllCustomers', _Arr([]),
    Customers, TypeInfo(TDtoCustomerArray));
  ShowStatus(Log, status);
  ShowCustomers(Log, Customers);

  Head(Log, 'GetCustomersByCity - one parameter  ->  TDtoCustomerArray');
  Customers := nil;
  status := ParseDynArray('GetCustomersByCity', _Arr(['Wegberg']),
    Customers, TypeInfo(TDtoCustomerArray));
  ShowStatus(Log, status);
  ShowCustomers(Log, Customers);

  Head(Log, 'GetCustomersByCity - no match, and it says so');
  Customers := nil;
  status := ParseDynArray('GetCustomersByCity', _Arr(['Nowhere']),
    Customers, TypeInfo(TDtoCustomerArray));
  ShowStatus(Log, status);
  ShowCustomers(Log, Customers);

  Head(Log, 'GetTurnoverPerCustomer - join, group by, having  ->  TDtoTurnoverArray');
  Turnover := nil;
  status := ParseDynArray('GetTurnoverPerCustomer', _Arr([1000]),
    Turnover, TypeInfo(TDtoTurnoverArray));
  ShowStatus(Log, status);
  for i := 0 to high(Turnover) do
    Log.Add(Format('  %-24s %-12s %2d invoices  %10.2f',
      [U(Turnover[i].Name), U(Turnover[i].City),
       Turnover[i].InvoiceCount, Turnover[i].Turnover]));

  { the client has no way to say "date": JSON carries a string. The template
    declares it, so the server makes a varDate of it before binding }
  Head(Log, 'GetInvoicesSince - the parameter is declared a date  ->  TDtoInvoiceArray');
  Invoices := nil;
  status := ParseDynArray('GetInvoicesSince', _Arr(['2026-01-01']),
    Invoices, TypeInfo(TDtoInvoiceArray));
  ShowStatus(Log, status);
  for i := 0 to high(Invoices) do
    Log.Add(Format('  %-12s %-24s %10.2f',
      [U(Invoices[i].InvoiceDate), U(Invoices[i].Name), Invoices[i].Amount]));

  Head(Log, 'GetInvoicesSince - a value the declaration refuses');
  Invoices := nil;
  status := ParseDynArray('GetInvoicesSince', _Arr(['31. August']),
    Invoices, TypeInfo(TDtoInvoiceArray));
  ShowStatus(Log, status);
end;

procedure Writes(Log: TStrings);
var
  Customers: TDtoCustomerArray;
begin
  Head(Log, 'AddCustomer / UpdateCustomerCity / DeleteCustomer');

  if Succeeded(SqlTool.WriteDataForAction('AddCustomer',
       _Arr(['Testfirma GmbH', 'Kevelaer']))) then
    Log.Add('  inserted');

  Customers := nil;
  ParseDynArray('GetCustomersByCity', _Arr(['Kevelaer']),
    Customers, TypeInfo(TDtoCustomerArray));
  ShowCustomers(Log, Customers);
  if Customers = nil then
    exit;

  if Succeeded(SqlTool.WriteDataForAction('UpdateCustomerCity',
       _Arr(['Winterberg', Customers[0].ID]))) then
    Log.Add('  moved to Winterberg');

  if Succeeded(SqlTool.WriteDataForAction('DeleteCustomer',
       _Arr([Customers[0].ID]))) then
    Log.Add('  deleted again');

  { an update that matched no row is not an error, and now says exactly that }
  Log.Add('  update on a missing row: ' + U(ToText(
    SqlTool.WriteDataForAction('UpdateCustomerCity',
      _Arr(['Nowhere', 999999])))));
end;

{ The other direction: here the client does NOT name the values one by one.
  It fills a record and hands it over, and the server takes the fields apart
  again - by name, with the types the record declared.

  Compare these with Writes() above: the same insert, once as a list of loose
  values and once as a record. The list is shorter for two columns and stops
  scaling at about six; the record does not care how many fields it has, and
  it carries its types.

  Three of the four keys have no statement in the registry at all.

  Every one of them starts with Orm: that prefix is what marks a key as one
  that makes a record - or a key - travel, and DeleteCustomer a few lines
  below is the ordinary statement it can now sit next to without either
  being mistaken for the other. }
procedure RecordWrites(Log: TStrings);
var
  cust, back: TDtoCustomer;
  inv: TDtoInvoiceRow;
  found: TDtoCustomerArray;
  status: TSqlStatus;
begin
  Head(Log, 'OrmAddTDtoCustomer - no statement at all, generated on arrival');
  cust.ID := 0; // filled by the database, and the insert does not name it
  cust.Name := 'Rekord GmbH';
  cust.City := 'Xanten';
  status := WriteRecord('OrmAddTDtoCustomer', cust, TypeInfo(TDtoCustomer));
  ShowStatus(Log, status);

  found := nil;
  ParseDynArray('GetCustomersByCity', _Arr(['Xanten']),
    found, TypeInfo(TDtoCustomerArray));
  ShowCustomers(Log, found);
  if found = nil then
    exit;

  Head(Log, 'OrmUpdateTDtoCustomer - generated too, ID goes to the where');
  cust.ID := found[0].ID;
  cust.City := 'Goch';
  status := WriteRecord('OrmUpdateTDtoCustomer', cust, TypeInfo(TDtoCustomer));
  ShowStatus(Log, status);
  found := nil;
  ParseDynArray('GetCustomersByCity', _Arr(['Goch']),
    found, TypeInfo(TDtoCustomerArray));
  ShowCustomers(Log, found);

  { The point of the whole exercise: InvoiceDate is a TDateTime here and is
    bound as a date, not as text. Nothing in the call says so - the record
    does, and the server reads the record back into the same type. }
  Head(Log, 'OrmAddTDtoInvoiceRow - a TDateTime and a currency, bound as such');
  inv.CustomerID := found[0].ID;
  inv.Amount := 1234.56;
  inv.InvoiceDate := EncodeDate(2026, 8, 31) + EncodeTime(14, 30, 0, 0);
  status := WriteRecord('OrmAddTDtoInvoiceRow', inv, TypeInfo(TDtoInvoiceRow));
  ShowStatus(Log, status);

  { the same shape the long way, with a written statement }
  Head(Log, 'OrmUpdateCustomerRecord - the written statement, same record');
  cust.City := 'Drolshagen';
  ShowStatus(Log,
    WriteRecord('OrmUpdateCustomerRecord', cust, TypeInfo(TDtoCustomer)));
  found := nil;
  ParseDynArray('GetCustomersByCity', _Arr(['Drolshagen']),
    found, TypeInfo(TDtoCustomerArray));
  ShowCustomers(Log, found);

  { The other direction, and the one that is NOT a mirror image: nothing is
    sent but the key. Which columns to read is the record type's business,
    and the server knows it from the template - the same thing an ORM does
    when it sends a list of field names rather than a record. }
  Head(Log, 'OrmRetrieveTDtoCustomer - the key goes out, the record comes back');
  back.ID := 0;
  back.Name := '';
  back.City := '';
  status := RetrieveRecord('OrmRetrieveTDtoCustomer', found[0].ID,
    back, TypeInfo(TDtoCustomer));
  ShowStatus(Log, status);
  Log.Add(U(FormatUtf8('  ID % / % / %', [back.ID, back.Name, back.City])));

  Head(Log, 'the same key on a row that is not there');
  ShowStatus(Log, RetrieveRecord('OrmRetrieveTDtoCustomer', 999999,
    back, TypeInfo(TDtoCustomer)));

  Head(Log, 'the wrong method for a record key, and the wrong record for a key');
  Log.Add('  WriteDataForAction on a record key -> ' + U(ToText(
    SqlTool.WriteDataForAction('OrmAddTDtoCustomer', _Arr(['x', 'y'])))));
  Log.Add('  WriteRecord on a value list key   -> ' + U(ToText(
    WriteRecord('AddCustomer', cust, TypeInfo(TDtoCustomer)))));

  { and the tidy-up is the fourth verb: the row this procedure created goes
    out through OrmDeleteTDtoCustomer, which carries no statement either }
  Head(Log, 'OrmDeleteTDtoCustomer - the key again, and nothing else');
  ShowStatus(Log, DeleteRecord('OrmDeleteTDtoCustomer', found[0].ID));
  Head(Log, 'and the same delete once more, on a key that is gone');
  ShowStatus(Log, DeleteRecord('OrmDeleteTDtoCustomer', found[0].ID));
end;

procedure Introspection(Log: TStrings);
const
  SEP: RawUtf8 = ', ';
begin
  Head(Log, 'AvailableActions - what can this server answer?');
  Log.Add('  ' + U(RawUtf8ArrayToCsv(SqlTool.AvailableActions, SEP)));
end;

procedure RunAllActions(Log: TStrings);
begin
  Selects(Log);
  Writes(Log);
  RecordWrites(Log);
  Introspection(Log);
end;

procedure RunUnknownAction(Log: TStrings);
var
  Customers: TDtoCustomerArray;
begin
  Head(Log, 'unknown and empty action keys - answers, not exceptions');
  Customers := nil;
  Log.Add('  DropEverything -> ' + U(ToText(
    ParseDynArray('DropEverything', _Arr([]),
      Customers, TypeInfo(TDtoCustomerArray)))));
  Log.Add('  (empty key)    -> ' + U(ToText(
    ParseDynArray('', _Arr([]),
      Customers, TypeInfo(TDtoCustomerArray)))));
end;

end.
