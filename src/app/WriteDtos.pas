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
    the name and the server answers sqlFailed

  Registered from TEXT, not from TypeInfo alone. FPC only emits the names of
  a record's fields as extended RTTI on trunk - mORMot defines
  HASEXTRECORDRTTI for 3.3 and 3.4 and for nothing else, and without it
  TRttiInfo.RecordAllFields returns nil. A type registered by TypeInfo would
  then arrive with no properties at all: the editor's record dialog opens on
  zero fields, and the server generates a statement that names no column. The
  declaration below is what a stock FPC 3.2 build has instead, and what a
  trunk build reads identically - so both produce the same record.

  The declarations are packed, and so are the records: RegisterFromText lays
  the fields out end to end and refuses the registration when the result is
  not the size the RTTI reports. A field added above but not below therefore
  fails loudly at startup rather than quietly shifting a value. }

interface

uses
  mormot.core.base,
  mormot.core.rtti,
  { not used by name below, and not optional: RegisterFromText resolves the
    field types through the JSON serializer's own RTTI class, which
    mormot.core.json installs in ITS initialization. Naming the unit here is
    what orders the two - without it this unit may register first, and the
    registration faults }
  mormot.core.json;

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

const
  { the field names and types as text, in declaration order - see the note at
    the top of this unit for why the TypeInfo() alone will not do }
  _TDtoCustomer =
    'ID: integer; Name: RawUtf8; City: RawUtf8';
  _TDtoInvoiceRow =
    'CustomerID: integer; Amount: currency; InvoiceDate: TDateTime';
  _TDtoArtikel =
    'ID: integer; ArtNr: integer; ArtName: RawUtf8; Kind: RawUtf8';

initialization
  { the server finds these by name and nothing else, so they have to be here }
  Rtti.RegisterFromText([
    TypeInfo(TDtoCustomer),   _TDtoCustomer,
    TypeInfo(TDtoInvoiceRow), _TDtoInvoiceRow,
    TypeInfo(TDtoArtikel),    _TDtoArtikel]);

end.
