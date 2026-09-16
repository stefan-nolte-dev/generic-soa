-- The four tables the templates in templates_mssql.sql read, as T-SQL for
-- SQL Server. Nothing in the project creates them: the mssql profile points at
-- a database that already exists, and this script is here so that the profile
-- can be tried out at all. Run it once against a database you may write to:
--   sqlcmd -S <server> -d <database> -i templates_mssql_schema.sql
-- The rows are made up. Drop the tables again when you are done with them.

if object_id('dbo.Product', 'U') is not null drop table dbo.Product;
if object_id('dbo.ProductName', 'U') is not null drop table dbo.ProductName;
if object_id('dbo.ProductGroup', 'U') is not null drop table dbo.ProductGroup;
if object_id('dbo.Supplier', 'U') is not null drop table dbo.Supplier;
go

create table dbo.ProductGroup (
  ProductGroup_ID int identity(1,1) primary key,
  GroupCode       varchar(10)  not null,
  GroupName       varchar(80)  not null);
go

create table dbo.ProductName (
  ProductName_ID int identity(1,1) primary key,
  Name           varchar(80)  not null,
  Description    varchar(255) null);
go

create table dbo.Product (
  Product_ID     int identity(1,1) primary key,
  PartNo         varchar(30)  not null,
  ListPrice      decimal(10,2) null,
  ProductName_ID int not null
    references dbo.ProductName(ProductName_ID));
go

create table dbo.Supplier (
  Supplier_ID int identity(1,1) primary key,
  VendorNo    int          null,
  Name        varchar(80)  null,
  PostCode    varchar(10)  null,
  City        varchar(80)  null);
go

insert into dbo.ProductGroup (GroupCode, GroupName) values
  ('SAW', 'Saw blades'), ('DRL', 'Drills'), ('MIL', 'Milling cutters');
go

insert into dbo.ProductName (Name, Description) values
  ('Circular saw blade', 'Carbide tipped, for panel saws'),
  ('Groove cutter',      'Adjustable width'),
  ('Spiral drill',       'HSS, for hardwood');
go

insert into dbo.Product (PartNo, ListPrice, ProductName_ID) values
  ('SAW-300-96',  184.50, 1), ('SAW-350-108', 229.00, 1),
  ('SAW-400-120', 312.75, 1), ('GRV-125-12',   96.40, 2),
  ('GRV-160-16',  118.90, 2), ('DRL-08-HSS',   14.20, 3);
go

insert into dbo.Supplier (VendorNo, Name, PostCode, City) values
  (1001, 'Bergmann Werkzeuge',     '41844', 'Wegberg'),
  (1002, 'Ostwald Holzbearbeitung','32756', 'Detmold'),
  (1003, 'Niederrhein Tischlerei', '47906', 'Kempen');
go
