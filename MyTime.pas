{ ************************************************************************

  This file is copyrighted 2011 by Mark Griffiths. Permission is hereby
  granted to use, modify, redistribute and create derivative works
  provided this attribution is not removed.

  ************************************************************************ }

unit MyTime;

interface

Uses Forms, WinTypes, SysUtils, MyStr, DateUtils, Controls, ComCtrls;

Type
     TUnixTime = Cardinal;

Function SystemTimeAsUnixTime: TUnixTime;

implementation

Function TimeStampToUnixTime(TimeStamp: TTimeStamp): TUnixTime;
begin
  result:= (TimeStamp.Date - 719163) * 86400 + TimeStamp.Time div 1000;
end;

Function SystemTimeToTimeStamp(SystemTime: TSystemTime): TTimeStamp;
begin
  result:= DateTimeToTimeStamp(SystemTimeToDateTime(SystemTime));
end;

Function SystemTimeToUnixTime(SystemTime: TSystemTime): TUnixTime;
begin
  result:= TimeStampToUnixTime(SystemTimeToTimeStamp(SystemTime));
end;

Function SystemTimeAsUnixTime: TUnixTime;
var SystemTime: TSystemTime;
begin
  GetSystemTime(SystemTime);
  Result:= SystemTimeToUnixTime(SystemTime);
end;


end.
