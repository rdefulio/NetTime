{ ************************************************************************

  This file is copyrighted 2011 by Mark Griffiths. Permission is hereby
  granted to use, modify, redistribute and create derivative works
  provided this attribution is not removed.

  ************************************************************************ }

unit MyStr;

interface

Uses Windows, SysUtils, Classes, Graphics;

Const crlf = #13#10;

Function Iff(Bool: Boolean; ValueIfTrue: String; ValueIfFalse: String = ''): String; Overload;

Function CompareVersionStrings(Ver1, Ver2: String): Integer;

implementation

Function First(MainString: String; sep: String): String;
var i: integer;
begin
  i:= Pos(sep, MainString);
  if i > 0 then
    First:= Copy(MainString, 1, i - 1)
  else
    First:= MainString;
end;

Function Rest(MainString: String; sep: String): String;
var i: integer;
begin
  i:= Pos(sep, MainString);
  if i > 0 then
//    Rest:= Copy(MainString, i+length(sep), length(MainString)-(i-(Length(sep)-1)))
    Rest:= Copy(MainString, i+length(sep), length(MainString)-(i+(Length(sep)-1)))
  else
    Rest:= '';
end;

Function Iff(Bool: Boolean; ValueIfTrue: String; ValueIfFalse: String = ''): String;
begin
  if Bool then
    Result:= ValueIfTrue
  else
    Result:= ValueIfFalse;
end;

Function CompareVersionStrings(Ver1, Ver2: String): Integer;
begin
  Result:= 0;
  while (Result = 0) and ((Ver1 <> '') or (Ver2 <> '')) do
    begin
      Result:= StrToIntDef(First(Ver1, '.'), 0) - StrToIntDef(First(Ver2, '.'), 0);

      if Result = 0 then
        begin
          Ver1:= Rest(Ver1, '.');
          Ver2:= Rest(Ver2, '.');
        end;
    end;
end;

end.
