{ ************************************************************************

  NetTime is copyrighted by Graham Mainwaring. Permission is hereby
  granted to use, modify, redistribute and create derivative works
  provided this attribution is not removed. I also request that if you
  make any useful changes, please e-mail the diffs to graham@mhn.org
  so that I can include them in an 'official' release.

  Modifications Copyright 2011 - Mark Griffiths

  ************************************************************************ }

unit timeconv;

interface

Uses Classes;

const
  MillisecondsPerSecond       = 1000;
  MillisecondsPerMinute       = 60 * MillisecondsPerSecond;
  MillisecondsPerHour         = 60 * MillisecondsPerMinute;
  MillisecondsPerDay          = 24 * MillisecondsPerHour;
  MillisecondsPerWeek         = 7 * MillisecondsPerDay;
  MillisecondsPerYear         = 365 * Int64(MillisecondsPerDay);  // Ignoring leap years!

  UnitsCount = 7;

  // Unit Indexes
  ui_Milliseconds             = 0;
  ui_Seconds                  = 1;
  ui_Minutes                  = 2;
  ui_Hours                    = 3;
  ui_Days                     = 4;
  ui_Weeks                    = 5;
  ui_Years                    = 6;

  UnitValues: Array[0..UnitsCount-1] of Int64 =
              (1,
               MillisecondsPerSecond,
               MillisecondsPerMinute,
               MillisecondsPerHour,
               MillisecondsPerDay,
               MillisecondsPerWeek,
               MillisecondsPerYear);

  UnitsStrings: Array[0..UnitsCount-1] of String =
                ('milliseconds',
                 'seconds',
                 'minutes',
                 'hours',
                 'days',
                 'weeks',
                 'years');

  UnitsShortStrings: array[0..UnitsCount-1] of String =
                     ('ms',
                      's',
                      'm',
                      'h',
                      'd',
                      'w',
                      'y');

type
  TNTPTimestamp = record
    Seconds: longword;
    SubSeconds: longword;
  end;

Procedure ValueToBaseAndUnits(Value: Int64; var Base: Single; var Units: Integer); Overload;
Procedure ValueToBaseAndUnits(Value: Int64; var Base: Integer; var Units: Integer); Overload;
Function BaseAndUnitsToValue(Base: Single; Units: Integer): Int64;

function UnixTimeToDateTime(ut: longword): TDateTime;
function DateTimeToUnixTime(dt: TDateTime): longword;
function RFC868TimeToDateTime(rt: longint): TDateTime;
function DateTimeToRFC868Time(dt: TDateTime): longword;
function NTPToDateTime(const ntp: TNTPTimestamp): TDateTime;
function DateTimeToNTP(const dt: TDateTime): TNTPTimestamp;
function SecondsApart(const t1, t2: TDateTime): int64;
function SecondsApartAbs(const t1, t2: TDateTime): int64;
function MilliSecondsApart(const t1, t2: TDateTime): int64;
function MilliSecondsApartAbs(const t1, t2: TDateTime): int64;
function GetOffsetStr(OffSet: int64): string;
function SecondsToStr(Seconds: Integer): string;
Procedure LoadUnitStrings(Strings: TStrings; Start: Integer = 0; Finish: Integer = UnitsCount - 1);


implementation

uses Windows, WinSock, SysUtils;

procedure SwapBytes(var b1, b2: byte);

var
  tmp: byte;

begin
  tmp:= b1;
  b1:= b2;
  b2:= tmp;
end;

function SecondsApart(const t1, t2: TDateTime): int64;
var
  st: TSystemTime;
  ft1, ft2: TFileTime;
begin
  DateTimeToSystemTime(t1, st);
  SystemTimeToFileTime(st, ft1);
  DateTimeToSystemTime(t2, st);
  SystemTimeToFileTime(st, ft2);
  result:= (int64(ft2) - int64(ft1)) div int64(10000000);
end;

function SecondsApartAbs(const t1, t2: TDateTime): int64;
begin
  result:= Abs(SecondsApart(t1, t2));
end;

function MilliSecondsApart(const t1, t2: TDateTime): int64;
var
  st: TSystemTime;
  ft1, ft2: TFileTime;
begin
  DateTimeToSystemTime(t1, st);
  SystemTimeToFileTime(st, ft1);
  DateTimeToSystemTime(t2, st);
  SystemTimeToFileTime(st, ft2);
  result:= (int64(ft2) - int64(ft1)) div int64(10000);
end;

function MilliSecondsApartAbs(const t1, t2: TDateTime): int64;
begin
  result:= Abs(MilliSecondsApart(t1, t2));
end;

const
  BaseDate1970 = 11644473600;
  BaseDate1900 = 9435484800;

function BaseDate(rfc: boolean): int64;
begin
  if rfc then
    result:= BaseDate1900
  else
    result:= BaseDate1970;
end;

function ConvertToDateTime(rfc: boolean; ut: longword): TDateTime;

var
  utctime: int64;
  localtime: int64;
  systemtime: TSystemTime;

begin
  utctime:= (int64(ut) + BaseDate(rfc));
  utctime:= utctime * int64(10000000);
  FileTimeToLocalFileTime(TFileTime(utctime), TFileTime(localtime));
  FileTimeToSystemTime(TFileTime(localtime), systemtime);
  result:= SystemTimeToDateTime(systemtime);
end;

function ConvertFromDateTime(rfc: boolean; dt: TDateTime): longword;

var
  utctime: int64;
  localtime: int64;
  systemtime: TSystemTime;

begin
  DateTimeToSystemTime(dt, systemtime);
  SystemTimeToFileTime(systemtime, TFileTime(localtime));
  LocalFileTimeToFileTime(TFileTime(localtime), TFileTime(utctime));
  utctime:= utctime div int64(10000000);
  result:= utctime - BaseDate(rfc);
end;

Procedure ValueToBaseAndUnits(Value: Int64; var Base: Single; var Units: Integer);
var Negative: Boolean;
begin
  Negative:= Value < 0;

  if Negative then
    Value:= - Value;

  Units:= 0;

  while (Units < UnitsCount - 1) and (Value > (2 * UnitValues[Units+1])) do
    Inc(Units);

  Base:= Value / UnitValues[Units];

  if Negative then
    Base:= - Base;
end;

Procedure ValueToBaseAndUnits(Value: Int64; var Base: Integer; var Units: Integer);
var Temp: Single;
begin
  ValueToBaseAndUnits(Value, Temp, Units);
  Base:= Round(Temp);
end;

Function BaseAndUnitsToValue(Base: Single; Units: Integer): Int64;
begin
  Assert(Units in [0..UnitsCount-1]);

  Result:= Round(Base * UnitValues[Units]);
end;

function UnixTimeToDateTime(ut: longword): TDateTime;
begin
  result:= ConvertToDateTime(false, ut);
end;

function DateTimeToUnixTime(dt: TDateTime): longword;
begin
  result:= ConvertFromDateTime(false, dt);
end;

function RFC868TimeToDateTime(rt: longint): TDateTime;

var
  nt: longword;

begin
  nt:= rt;
  nt:= ntohl(nt);
  result:= ConvertToDateTime(true, nt);
end;

function DateTimeToRFC868Time(dt: TDateTime): longword;
begin
  result:= ConvertFromDateTime(true, dt);
  result:= htonl(result);
end;

const
  OneMil = $100000000 div 1000; // ratio of milliseconds to secs/2^32

function NTPToDateTime(const ntp: TNTPTimestamp): TDateTime;

var
  timepart: longword;
  time: TSystemTime;

begin
  // first, figure out the "rough" time in seconds
  timepart:= ntohl(ntp.Seconds);
  DateTimeToSystemTime(ConvertToDateTime(true, timepart), time);
  // now, add the "fine" time in 2^32nds of a second
  timepart:= ntohl(ntp.SubSeconds);
  timepart:= timepart div OneMil;
  time.wMilliseconds:= time.wMilliseconds + timepart;
  time.wSecond:= time.wSecond + (time.wMilliseconds div 1000);
  time.wMilliseconds:= time.wMilliseconds mod 1000;
  result:= SystemTimeToDateTime(time);
end;

function DateTimeToNTP(const dt: TDateTime): TNTPTimestamp;

var
  time: TSystemTime;

begin
  result.Seconds:= htonl(ConvertFromDateTime(true, dt));
  DateTimeToSystemTime(dt, time);
  result.SubSeconds:= htonl(time.wMilliseconds * OneMil);
end;

function GetOffsetStr(OffSet: int64): string;
var Base: Single;
    Units: Integer;
begin
  ValueToBaseAndUnits(Offset, Base, Units);

  Result:= FloatToStrF(Base, ffGeneral, 4, 4)+UnitsShortStrings[Units];

  if OffSet >= 0 then
    Result:= '+' + Result;
end;

function SecondsToStr(Seconds: Integer): string;
var
  Value: Integer;
begin
  result:= '';

  Value:= Seconds div 86400;
  Seconds:= Seconds mod 86400;
  if Value > 0 then
    result:= IntToStr(Value) + 'd ';

  Value:= Seconds div 3600;
  Seconds:= Seconds mod 3600;

  if (Value > 0) or (result <> '') then
    result:= result + IntToStr(Value) + 'h ';

  Value:= Seconds div 60;
  Seconds:= Seconds mod 60;

  if (Value > 0) or (result <> '') then
    result:= result + IntToStr(Value) + 'm ';

  result:= result + IntToStr(Seconds) + 's';
end;

Procedure LoadUnitStrings(Strings: TStrings; Start: Integer = 0; Finish: Integer = UnitsCount - 1);
var i: Integer;
begin
  Strings.Clear;

  for i:= Start to Finish do
    Strings.Add(UnitsStrings[i]);
end;

end.
