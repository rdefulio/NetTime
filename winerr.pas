unit winerr;

interface

function errtostr(const err: HResult): string;

implementation

uses Windows, SysUtils;

function errtostr(const err: HResult): string;
begin
  SetLength(result, 255);
  FormatMessage(FORMAT_MESSAGE_FROM_SYSTEM, nil, err, 0, pchar(result), 255, nil);
  SetLength(result, strlen(pchar(result)));
end;

end.
