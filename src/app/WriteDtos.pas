unit WriteDtos;

{$I mormot.defines.inc}

{ The records that travel from the client to the server - and unlike
  ClientDtos, this unit is used by BOTH sides.

  Reading, only the client needs the type: the server sends JSON and never
  names the shape. Writing, someone has to turn JSON back into typed values,
  and that someone is the server. So the declaration is shared - and it sits
  next to the service contract, visible to exactly whoever that is.

  Shared is the declaration, not any code: the server names none of these
  records, it finds them by the name in the RecordType column. Two rules:

  - the field names have to match the table's column names (or the :Names of
    a written statement)
  - every record has to be registered below, or Rtti.FindName cannot resolve
    the name and the server answers sqlFailed }

interface

uses
  mormot.core.base,
  mormot.core.rtti;

type

  /// a Customer row - read with GetAllCustomers, written with AddTDtoCustomer
  // - the SAME record both ways, declared once: the array goes out through
  // ParseDynArray, one element comes back through WriteRecord
  // - it may cover a subset of the columns; a generated statement names what
  // this record has and nothing else
  TDtoCustomer = packed record
    ID: integer;
    Name: RawUtf8;
    City: RawUtf8;
  end;
  TDtoCustomerArray = array of TDtoCustomer;

  /// an Invoice row, for AddTDtoInvoiceRow
  // - the interesting one: a real TDateTime and a real currency, and both
  // survive as such into the bind. That is what this direction is for
  TDtoInvoiceRow = packed record
    CustomerID: integer;
    Amount: currency;
    InvoiceDate: TDateTime;
  end;

  TDtoArtikel = packed record
    ID:integer;
    ArtNr: integer;
    ArtName: RawUtf8;
    Kind: RawUtf8;
  end;

implementation

initialization
  { the server finds these by name and nothing else, so they have to be here }
  Rtti.RegisterTypes([
    TypeInfo(TDtoCustomer),
    TypeInfo(TDtoInvoiceRow),
    TypeInfo(TDtoArtikel)]);

end.
