unit IsWinNT;

interface

function IsWindowsNT: boolean;

implementation

uses SysUtils, Windows;

function IsWindowsNT: boolean;

var
  VerInfo: TOsVersionInfo;

begin
  VerInfo.dwOSVersionInfoSize:= sizeof(VerInfo);
  if not GetVersionEx(VerInfo) then
    raise exception.create('Could not get OS version info');
  result:= (VerInfo.dwPlatformID >= 2); // treat future platforms as NT
end;

end.
