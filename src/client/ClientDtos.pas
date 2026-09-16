unit ClientDtos;

{$I mormot.defines.inc}

{ The READ-only records of this sample - and note where they live: in the
  client, and nowhere else.

  The server has no idea these exist. It answers with the JSON its database
  produced, and the shape is decided here, by whoever consumes it. Adding a
  query adds a record here and nothing anywhere else - no interface to extend,
  no layer to mirror it through, no converters between them.

  The field names have to match the column names of the statement; the
  editor's "Typ aus Ergebnis erzeugen" writes the declaration from a result
  set so they cannot drift.

  TDtoCustomer is NOT here: that shape is written as well as read, so it has
  to be known on both sides and is declared once, in WriteDtos.

  There is no Rtti.RegisterFromText, and that has a condition attached. mORMot
  reads the record layout from extended record RTTI, which its own defines
  gate as HASEXTRECORDRTTI: Delphi 2010+ and FPC trunk 3.3/3.4, but NOT FPC
  3.2.x - measured here, 3.3.1 parses and 3.2.3 parses nothing. On Delphi
  there is a second condition flagged in mORMot's own source: reading the
  field table "may need $RTTI EXPLICIT FIELDS([vcPublic])". Untested - this
  machine has no Delphi. If records come back empty there, start with that. }

interface

uses
  mormot.core.base;

type

  /// rows of GetTurnoverPerCustomer - the join with the grouped aggregate
  TDtoTurnover = packed record
    Name: RawUtf8;
    City: RawUtf8;
    InvoiceCount: integer;
    Turnover: double;
  end;
  TDtoTurnoverArray = array of TDtoTurnover;

  /// rows of GetInvoicesSince - the query whose parameter is declared 'date'
  // - note InvoiceDate is RawUtf8 here and not TDateTime: what comes back is
  // JSON, and JSON has no date. The declaration matters on the way IN, where
  // it decides how the value is bound; on the way out the shape is whatever
  // the statement selected
  TDtoInvoice = packed record
    ID: integer;
    Name: RawUtf8;
    Amount: double;
    InvoiceDate: RawUtf8;
  end;
  TDtoInvoiceArray = array of TDtoInvoice;

  { straight out of the editor's type generator, on GetAlleMitarbeiter -
    copied in, and nothing else was needed }
  TDtoMitarbeiter = packed record
    ID: integer;
    Name: RawUtf8;
    Abteilung: RawUtf8;
    Eintritt: RawUtf8;
    Gehalt: double;
  end;
  TDtoMitarbeiterArray = array of TDtoMitarbeiter;

  TDtoAmountDateCustomer4OfInvoice = packed record
    Amount: double;
    InvoiceDate: RawUtf8;
  end;
  TDtoAmountDateCustomer4OfInvoiceArray = array of TDtoAmountDateCustomer4OfInvoice;

implementation

end.
