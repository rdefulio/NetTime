{ ************************************************************************

  This file is copyrighted 2011, 2012 by Mark Griffiths. Permission is hereby
  granted to use, modify, redistribute and create derivative works
  provided this attribution is not removed.

  ************************************************************************ }

unit WinUtils;

interface

uses Forms, Windows, SysUtils, WinSvc, Registry;

function HaveAdminPrivileges: Boolean;
procedure MySleep(delay: integer);
Function RunningOnWin2000: Boolean;
function UACEnabled: Boolean;

type
  TOSVersionInfoExA = record
    case integer of
      0:
        (OldVer: TOSVersionInfoA);
      1:
        (dwOSVersionInfoSize: DWORD;
          dwMajorVersion: DWORD;
          dwMinorVersion: DWORD;
          dwBuildNumber: DWORD;
          dwPlatformId: DWORD;
          szCSDVersion: array [0 .. 127] of AnsiChar; { Maintenance string for PSS usage }
          wServicePackMajor: Short;
          wServicePackMinor: Short;
          wSuiteMask: Short;
          wProductType: Byte;
          wReserved: Byte);
  end;

implementation

function RegReadKey(Key: HKEY; KeyName, ValueName: string): string;
var
  Reg: TRegistry;
begin
  Reg:= TRegistry.Create;
  Reg.RootKey:= Key;
  Reg.Access:= KEY_READ;
  if Reg.OpenKey(KeyName, False) then
    begin
      try
        Result:= Reg.ReadString(ValueName);
      except
        on Exception do
          Result:= '';
      end;
    end
  else
    Result:= '';
  Reg.Free;
end;

function RegReadInteger(Key: HKEY; KeyName, ValueName: string): integer;
var
  Reg: TRegistry;
begin
  Reg:= TRegistry.Create;
  Reg.RootKey:= Key;
  Reg.Access:= KEY_READ;
  if Reg.OpenKey(KeyName, False) then
    begin
      try
        Result:= Reg.ReadInteger(ValueName);
      except
        on Exception do
          Result:= 0;
      end;
    end
  else
    Result:= 0;
  Reg.Free;
end;

function HaveAdminPrivileges: Boolean;
const
  Tested: Boolean = False;
  GotAdminPrivileges: Boolean = False;
var
  h: SC_HANDLE;
begin
  if Tested then
    begin
      Result:= GotAdminPrivileges;
      exit;
    end;

  Result:= False;
  if Win32Platform = VER_PLATFORM_WIN32_NT then
    begin
      h:= OpenSCManager(nil, nil, GENERIC_READ or GENERIC_WRITE or GENERIC_EXECUTE);
      if h <> 0 then
        begin
          Result:= True;
          CloseServiceHandle(h);
        end;
    end
  else
    Result:= True;

  GotAdminPrivileges:= Result;
  Tested:= True;
end;

procedure MySleep(delay: integer);
var
  TimeStart: Comp;
  ElapsedMSecs: Comp;
begin
  TimeStart:= TimeStamptoMSecs(DateTimeToTimeStamp(Now));
  repeat
    Application.ProcessMessages;
    Sleep(50);
    ElapsedMSecs:= TimeStamptoMSecs(DateTimeToTimeStamp(Now)) - TimeStart;
  until (ElapsedMSecs > delay) or (ElapsedMSecs < 0);
end;

Function RunningOnWin2000: Boolean;
var WinVer: TOSVersionInfoExA;
begin
  WinVer.dwOSVersionInfoSize:= Sizeof(WinVer);
  GetVersionExA(WinVer.OldVer);
  Result:= (WinVer.dwPlatformId = VER_PLATFORM_WIN32_NT) and (WinVer.dwMajorVersion >= 5);
end;

function RunningOnWindowsVista: Boolean;
var WinVer: TOSVersionInfoExA;
begin
  WinVer.dwOSVersionInfoSize:= Sizeof(WinVer);
  GetVersionExA(WinVer.OldVer);  // Fix for newer versions of Delphi
  Result:= (WinVer.dwPlatformId = VER_PLATFORM_WIN32_NT) and (WinVer.dwMajorVersion >= 6);
end;

function UACEnabled: Boolean;
begin
  Result:= RunningOnWindowsVista and
    (RegReadInteger(HKEY_LOCAL_MACHINE, 'Software\Microsoft\Windows\CurrentVersion\Policies\System', 'EnableLUA') <> 0);
end;

end.
