unit UpdateCheck;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, ComCtrls, MyTime, HttpProt, WinUtils,
  FileVersion, MyStr, ExtCtrls, Logging, NetTimeCommon, Registry,
  ShellAPI, WinsockUtil, Math;

var AutomaticUpdateChecksEnabled: Boolean;
    DaysBetweenUpdateChecks: Integer;

Function GetNextUpdateCheckDue: TUnixTime;
Procedure WriteUpdateCheckSettingsToRegistry;
Procedure CheckForUpdates(ManualUpdateCheck: Boolean);

implementation

var LastUpdateCheck: TUnixTime;

Procedure FixLastUpdateCheck;
begin
  // If the LastUpdateTime is too far into the future, ignore it!
  if LastUpdateCheck > (SystemTimeAsUnixTime + 900) then
    LastUpdateCheck:= 0;
end;

Function GetLastUpdateCheck: TUnixTime;
begin
  FixLastUpdateCheck;

  Result:= LastUpdateCheck;
end;

Function GetNextUpdateCheckDue: TUnixTime;
begin
  Result:= (TUnixTime(GetLastUpdateCheck) + TUnixTime(DaysBetweenUpdateChecks) * 86400);
end;

Procedure ReadUpdateCheckSettingsFromRegistry;
var reg: TRegistry;

  Function ReadInteger(Name: String; Default: Integer): Integer;
  begin
    try
      Result:= reg.ReadInteger(Name);
    except
      Result:= Default;
    end;
  end;

  Function ReadBool(Name: String; Default: Boolean): Boolean;
  begin
    try
      Result:= reg.ReadBool(Name);
    except
      Result:= Default;
    end;
  end;

begin
  reg:= TRegistry.Create;
  reg.RootKey:= HKEY_LOCAL_MACHINE;
  if reg.OpenKeyReadOnly(ProgramRegistryPath) then
    begin
      AutomaticUpdateChecksEnabled:=       ReadBool('AutomaticUpdateChecks', True);
      DaysBetweenUpdateChecks:=            ReadInteger('DaysBetweenUpdateChecks', DefaultDaysBetweenUpdateChecks);
      if DaysBetweenUpdateChecks < 1 then
        DaysBetweenUpdateChecks:= 1;
      LastUpdateCheck:=                    ReadInteger('LastUpdateCheck', 0);
      FixLastUpdateCheck;
    end
  else
    begin
      AutomaticUpdateChecksEnabled:= True;
      DaysBetweenUpdateChecks:= DefaultDaysBetweenUpdateChecks;
      LastUpdateCheck:= 0;
    end;
  reg.CloseKey;

  reg.RootKey:= HKEY_CURRENT_USER;
  if reg.OpenKeyReadOnly(ProgramRegistryPath) then
    begin
      LastUpdateCheck:= Max(LastUpdateCheck, ReadInteger('LastUpdateCheck', 0));
      FixLastUpdateCheck;
    end;

  reg.CloseKey;
  reg.Free;
end;

Procedure WriteUpdateCheckSettingsToRegistry;
var Reg: TRegistry;
begin
  reg:= TRegistry.Create;
  reg.RootKey:= HKEY_LOCAL_MACHINE;
  if reg.OpenKey(ProgramRegistryPath, True) then
    begin
      reg.WriteBool('AutomaticUpdateChecks', AutomaticUpdateChecksEnabled);
      reg.WriteInteger('DaysBetweenUpdateChecks', DaysBetweenUpdateChecks);
    end;
  reg.CloseKey;
  reg.Free;
end;

Function TimeTillNextUpdateCheck: Integer;
begin
  Assert(AutomaticUpdateChecksEnabled);

  Result:= (TUnixTime(GetLastUpdateCheck) + TUnixTime(DaysBetweenUpdateChecks) * 86400) - SystemTimeAsUnixTime;

  if Result < 3 then
    Result:= 3;
end;

Procedure CheckForUpdates(ManualUpdateCheck: Boolean);
var HttpCli: THttpCli;
    RcvdStream: TMemoryStream;
    VersionCheckData: TStringList;

  Procedure UpdateCheckFinished;

    Procedure WriteLastUpdateCheckToKey(RootKey: HKey);
    var reg: TRegistry;
    begin
      reg:= TRegistry.Create;
      reg.RootKey:= RootKey;
      if reg.OpenKey(ProgramRegistryPath, True) then
        reg.WriteInteger('LastUpdateCheck', LastUpdateCheck);
      reg.CloseKey;
      reg.Free;
    end;

  begin
    WriteLastUpdateCheckToKey(HKEY_LOCAL_MACHINE);
    WriteLastUpdateCheckToKey(HKEY_CURRENT_USER);
  end;

  Procedure LaunchWebSite;
  begin
    Application.ProcessMessages;
    LogMessage('Launching NetTime web site', log_Verbose);
    ShellExecute(0, 'open', 'http://www.timesynctool.com', nil, nil, SW_NORMAL);
  end;

  Procedure UpdateCheckError;
  var Msg: String;
  begin
    Msg:= 'Update Check Error: '+IntToStr(HttpCli.StatusCode) + crlf + crlf + HttpCli.ReasonPhrase;

    LogMessage(Msg, log_Verbose);

    if ManualUpdateCheck then
      begin
        if HttpCli.StatusCode = 404 then
          Msg:= Msg + crlf + crlf + 'Please check that your Internet connection is working!';

        Msg:= Msg + crlf + crlf + 'Would you like to manually check for updates on the NetTime web site?';

        if Application.MessageBox(PChar(Msg), 'Error', mb_YesNo) = IDYes then
          LaunchWebSite;
      end;
  end;

begin
  if ManualUpdateCheck then
    LogMessage('Manual Update Check', log_Verbose)
  else
    LogMessage('Automatic Update Check', log_Verbose);

  if HaveLocalAddress then
    begin
      // Set the last Update Check Time here so that we don't keep checking constantly if there is a failure.
      // We'll only save this value to the registry if we're successful - if we're not successful, it will then
      // check for updates straight away when NetTime is next started.
      LastUpdateCheck:= SystemTimeAsUnixTime;
    end;

  RcvdStream:= TMemoryStream.Create;
  HttpCli:= THttpCli.Create(nil);
  VersionCheckData:= TStringList.Create;

  try
    HttpCli.RcvdStream:= RcvdStream;

    HttpCli.URL:= 'www.timesynctool.com/updatecheck?'+GetCurrentFileVersionString;

    try
      HttpCli.Get;
    except
    end;

    if HttpCli.StatusCode <> 200 then
      begin
        UpdateCheckError;
        exit;
      end;

    RcvdStream.Seek(0, soFromBeginning);
    VersionCheckData.LoadFromStream(RcvdStream);

    if VersionCheckData.Count <= 0 then
      begin
        if ManualUpdateCheck then
          Application.MessageBox('Update Error: No Data Returned!', 'Error', 0);
        exit;
      end;

    UpdateCheckFinished;

    if CompareVersionStrings(VersionCheckData[0], GetCurrentFileVersionString) > 0 then
      begin
        LogMessage('Updated Version available: '+VersionCheckData[0], log_Verbose);
        if Application.MessageBox('An updated version of NetTime is now available!'#13#13'Would you like to visit the NetTime web site to download it now?', 'NetTime Update Available', mb_YesNo) = IDYes then
          begin
            LaunchWebSite;
            exit;
          end;
      end
    else
      begin
        LogMessage('No Update Available', log_Verbose);
        if ManualUpdateCheck then
          Application.MessageBox('No update available!', 'No Updates', 0);

        exit;
      end;
  finally
    FreeAndNil(VersionCheckData);
    FreeAndNil(HttpCli);
    FreeAndNil(RcvdStream);
  end;
end;

begin
  ReadUpdateCheckSettingsFromRegistry;
end.
