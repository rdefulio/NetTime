{ ************************************************************************

  NetTime is copyrighted by Graham Mainwaring. Permission is hereby
  granted to use, modify, redistribute and create derivative works
  provided this attribution is not removed. I also request that if you
  make any useful changes, please e-mail the diffs to graham@mhn.org
  so that I can include them in an 'official' release.

  Modifications Copyright 2011 - Mark Griffiths

  ************************************************************************ }

unit mutex;

interface

uses Windows, SysUtils;

function GetExclusivity(const name: string): boolean;
function CheckExclusivity(const name: string): boolean;
procedure ReleaseExclusivity(const name: string);

implementation

uses Classes;

var
  HeldHandles: TStringList;

function GetExclusivity(const name: string): boolean;
var
  res: HResult;
  sa: SECURITY_ATTRIBUTES;
  sd: SECURITY_DESCRIPTOR;
begin
  // 25/4/2011: Security code added so that the mutex can be accessed by limited access accounts!
  InitializeSecurityDescriptor(@sd, SECURITY_DESCRIPTOR_REVISION);
  SetSecurityDescriptorDacl(@sd, True, nil, False);
  sa.nLength:= SizeOf(sa);
  sa.lpSecurityDescriptor:= @sd;

  res:= CreateMutex(@sa, True, PChar(name));
  if (res = 0) or (GetLastError = ERROR_ALREADY_EXISTS) then
    begin
      result:= False;
      exit;
    end
  else
    begin
      HeldHandles.AddObject(name, TObject(res));
      result:= True;
    end;
end;

// This will just check to see if the Mutex already exists without creating it if it doesn't!
function CheckExclusivity(const name: string): boolean;
var
  res: HResult;
begin
  res:= OpenMutex(SYNCHRONIZE, False, PChar(name));
  result:= res = 0;

  if res <> 0 then
    CloseHandle(res);
end;

procedure ReleaseExclusivity(const name: string);
var
  idx: integer;
begin
  idx:= HeldHandles.IndexOf(name);
  if idx = -1 then
    raise exception.create('We do not hold this handle');
  CloseHandle(integer(HeldHandles.Objects[idx]));
  HeldHandles.Delete(idx);
end;

initialization

HeldHandles:= TStringList.create;

finalization

HeldHandles.Free;

end.
