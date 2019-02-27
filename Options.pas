{ ************************************************************************

  NetTime is copyrighted by Graham Mainwaring. Permission is hereby
  granted to use, modify, redistribute and create derivative works
  provided this attribution is not removed. I also request that if you
  make any useful changes, please e-mail the diffs to graham@mhn.org
  so that I can include them in an 'official' release.

  Modifications Copyright 2011, 2012 - Mark Griffiths

  ************************************************************************ }

unit Options;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  StdCtrls, Buttons, configobj, NetTimeCommon, Logging, IsWinNT, timeconv, Math, UpdateCheck;

type

  TfrmOptions = class;

  TfrmOptions = class(TForm)
    Label1: TLabel;
    edHostname: TEdit;
    Label2: TLabel;
    edSyncFreq: TEdit;
    Label3: TLabel;
    edLostSync: TEdit;
    Label5: TLabel;
    edRetry: TEdit;
    cbxProtocol: TComboBox;
    btnOK: TButton;
    btnCancel: TButton;
    cbxServer: TCheckBox;
    Label7: TLabel;
    edPort: TEdit;
    Label8: TLabel;
    Label9: TLabel;
    edHostname1: TEdit;
    cbxProtocol1: TComboBox;
    edPort1: TEdit;
    edHostname2: TEdit;
    cbxProtocol2: TComboBox;
    edPort2: TEdit;
    edHostname3: TEdit;
    cbxProtocol3: TComboBox;
    edPort3: TEdit;
    edHostname4: TEdit;
    cbxProtocol4: TComboBox;
    edPort4: TEdit;
    cbxShowInTray: TCheckBox;
    cbxServiceAutoStart: TCheckBox;
    Label12: TLabel;
    ddLogLevel: TComboBox;
    CbxDemoteServers: TCheckBox;
    edDemoteOnErrorCount: TEdit;
    Label6: TLabel;
    Label4: TLabel;
    edLargeAdjustmentThreshold: TEdit;
    ddLargeAdjustmentThresholdUnits: TComboBox;
    ddLargeAdjustmentAction: TComboBox;
    ddSyncFreqUnits: TComboBox;
    ddLostSyncUnits: TComboBox;
    ddRetryUnits: TComboBox;
    ViewLog: TButton;
    cbxAutomaticUpdateChecksEnabled: TCheckBox;
    edDaysBetweenUpdateChecks: TEdit;
    Label10: TLabel;
    CheckNow: TButton;
    cbxAlwaysProvideTime: TCheckBox;
    procedure FormShow(Sender: TObject);
    procedure btnOKClick(Sender: TObject);
    procedure btnHelpClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure cbxProtocolChange(Sender: TObject);
    procedure CbxDemoteServersClick(Sender: TObject);
    procedure ViewLogClick(Sender: TObject);
    procedure cbxAutomaticUpdateChecksEnabledClick(Sender: TObject);
    procedure CheckNowClick(Sender: TObject);
    procedure cbxServerClick(Sender: TObject);
    procedure cbxAlwaysProvideTimeClick(Sender: TObject);
  private
    ReadingFromObject: Boolean;
    Hostnames: array [0 .. MaxServers - 1] of TEdit;
    Protocols: array [0 .. MaxServers - 1] of TComboBox;
    Ports: array [0 .. MaxServers - 1] of TEdit;
  public
    co: TConfigObj;
    tt: TNetTimeServerBase;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure ReadFromRegistry;
    procedure ReadFromRunning(tt: TNetTimeServerBase);
    procedure ReadFromObject;
    procedure WriteToRegistry;
    procedure WriteToRunning(tt: TNetTimeServerBase);
    procedure WriteToObject;
  end;

implementation

{$R *.DFM}                                                                  
uses registry, timewrap, LogView;

constructor TfrmOptions.Create(AOwner: TComponent);
begin
  inherited;
  LoadUnitStrings(ddSyncFreqUnits.Items, ui_Seconds, ui_Days);
  LoadUnitStrings(ddRetryUnits.Items, ui_Seconds, ui_Days);
  LoadUnitStrings(ddLargeAdjustmentThresholdUnits.Items);
  LoadUnitStrings(ddLostSyncUnits.Items, ui_Minutes, ui_Years);
  co:= TConfigObj.Create;
  ReadFromObject;
end;

destructor TfrmOptions.Destroy;
begin
  co.Free;
  inherited;
end;

procedure TfrmOptions.FormShow(Sender: TObject);
begin
  if Assigned(tt) then
    ReadFromRunning(tt)
  else
    ReadFromRegistry;
end;

procedure TfrmOptions.ReadFromRegistry;
begin
  co.ReadFromRegistry;
  ReadFromObject;
end;

procedure TfrmOptions.ReadFromRunning(tt: TNetTimeServerBase);
begin
  co.ReadFromRegistry;
  co.ReadFromRunning(tt);
  ReadFromObject;
end;

procedure TfrmOptions.ReadFromObject;
var i: integer;

  procedure ReadServer(const n: integer);
  begin
    Hostnames[n].Text:= co.Servers[n].Hostname;
    Protocols[n].ItemIndex:= integer(co.Servers[n].Protocol);
    Ports[n].Text:= inttostr(co.Servers[n].Port);
  end;

begin
  ReadingFromObject:= True;

  for i:= 0 to co.ServerCount - 1 do
    ReadServer(i);

  edSyncFreq.Text:= IntToStr(co.SyncFreq);
  ddSyncFreqUnits.ItemIndex:= co.SyncFreqUnits - 1;

  edRetry.Text:= IntToStr(co.Retry);
  ddRetryUnits.ItemIndex:= co.RetryUnits - 1;

  CbxDemoteServers.Checked:= co.DemoteOnErrorCount > 0;
  if co.DemoteOnErrorCount > 0 then
    edDemoteOnErrorCount.Text:= inttostr(co.DemoteOnErrorCount)
  else
    edDemoteOnErrorCount.Text:= inttostr(DefaultDemoteOnErrorCount);

  cbxServer.Checked:= co.Server;
  cbxAlwaysProvideTime.Checked:= co.AlwaysProvideTime;
  cbxShowInTray.Checked:= co.LoadOnLogin;
  cbxServiceAutoStart.Visible:= IsWindowsNT;
  cbxServiceAutoStart.Checked:= co.ServiceOnBoot;

  edLostSync.Text:= IntToStr(co.LostSync);
  ddLostSyncUnits.ItemIndex:= co.LostSyncUnits - 2;

  edLargeAdjustmentThreshold.Text:= IntToStr(co.LargeAdjustmentThreshold);
  ddLargeAdjustmentThresholdUnits.ItemIndex:= co.LargeAdjustmentThresholdUnits;

  // The option to shut down NetTime is not shown by default because it can prevent the user from
  // being able to start NetTime in the first place.  The setting can be done through the registry initially and then
  // it will appear in NetTime.
  // If a user knows how to set the value in the registry, they should be able to take it back out again if
  // they have trouble starting NetTime.

  if (co.LargeAdjustmentAction = laa_Quit) and (ddLargeAdjustmentAction.Items.Count <= laa_Quit) then
    ddLargeAdjustmentAction.Items.Add('Shut Down NetTime');

  ddLargeAdjustmentAction.ItemIndex:= co.LargeAdjustmentAction;

  cbxAutomaticUpdateChecksEnabled.Checked:= AutomaticUpdateChecksEnabled;
  edDaysBetweenUpdateChecks.Text:= IntToStr(DaysBetweenUpdateChecks);

  ddLogLevel.ItemIndex:= co.LogLevel;

  ReadingFromObject:= False;
end;

procedure TfrmOptions.WriteToRegistry;
begin
  // WriteToObject;  // Disabled 2/5/2011 by MTG - was overwriting the changes that we've made - such as setting defaults and minimums!!!
  co.WriteToRegistry;
  WriteUpdateCheckSettingsToRegistry;
end;

procedure TfrmOptions.WriteToRunning(tt: TNetTimeServerBase);
begin
  // WriteToObject;  // Disabled 2/5/2011 by MTG - was overwriting the changes that we've made - such as setting defaults and minimums!!!
  co.WriteToRunning(tt);
end;

procedure TfrmOptions.WriteToObject;
var i: integer;

  procedure WriteServer(const n: integer);
  var
    Srv: TServerDef;
  begin
    if Hostnames[n].Text = '' then
      exit;
    Srv.Hostname:= Hostnames[n].Text;
    Srv.Protocol:= TTimeProto(Protocols[n].ItemIndex);
    Srv.Port:= StrToIntDef(Ports[n].Text, DefaultPortForProtocol(Srv.Protocol));
    co.AddServer(Srv);
  end;

begin
  co.ClearServerList;
  for i:= 0 to MaxServers - 1 do
    WriteServer(i);

  co.SyncFreq:= StrToIntDef(edSyncFreq.Text, DefaultSyncFreq);
  co.SyncFreqUnits:= ddSyncFreqUnits.ItemIndex + 1;

  co.Retry:= StrToIntDef(edRetry.Text, DefaultRetry);
  co.RetryUnits:= ddRetryUnits.ItemIndex + 1;

  if CbxDemoteServers.Checked then
    co.DemoteOnErrorCount:= StrToIntDef(edDemoteOnErrorCount.Text, DefaultDemoteOnErrorCount)
  else
    co.DemoteOnErrorCount:= 0;

  co.Server:= cbxServer.Checked;
  co.AlwaysProvideTime:= cbxAlwaysProvideTime.Checked;
  co.LoadOnLogin:= cbxShowInTray.Checked;
  co.ServiceOnBoot:= IsWindowsNT and cbxServiceAutoStart.Checked;

  co.LostSync:= StrToIntDef(edLostSync.Text, DefaultLostSync);
  co.LostSyncUnits:= ddLostSyncUnits.ItemIndex + 2;

  co.LargeAdjustmentThreshold:= StrToIntDef(edLargeAdjustmentThreshold.Text, DefaultLargeAdjustmentThreshold);
  co.LargeAdjustmentThresholdUnits:= ddLargeAdjustmentThresholdUnits.ItemIndex;
  co.LargeAdjustmentAction:= ddLargeAdjustmentAction.ItemIndex;

  AutomaticUpdateChecksEnabled:= cbxAutomaticUpdateChecksEnabled.Checked;
  DaysBetweenUpdateChecks:= StrToIntDef(edDaysBetweenUpdateChecks.Text, DefaultDaysBetweenUpdateChecks);
  if DaysBetweenUpdateChecks < 1 then
    DaysBetweenUpdateChecks:= 1;

  co.LogLevel:= ddLogLevel.ItemIndex;
end;

procedure TfrmOptions.btnOKClick(Sender: TObject);
var Problems: string;
    NewLostSync: Single;
    NewLostSyncUnits: Integer;

  function UsingNTPPool: Boolean;
  var
    i: integer;
  begin
    result:= False;

    for i:= 0 to co.ServerCount - 1 do
      if Pos('pool.ntp.org', LowerCase(co.Servers[i].Hostname)) > 0 then
        begin
          result:= True;
          Break;
        end;
  end;

begin
  WriteToObject;

  if UsingNTPPool and (BaseAndUnitsToValue(co.SyncFreq, co.SyncFreqUnits) < BaseAndUnitsToValue(MinNTPPoolSyncFreq, MinNTPPoolSyncFreqUnits)) then
    begin
      MessageDlg('The minimum update interval when using the NTP Pool Servers is '+IntToStr(MinNTPPoolSyncFreq)+' '+UnitsStrings[MinNTPPoolSyncFreqUnits]+'.'#13#10 +
        'If you require better accuracy for your system time, we recommend that you use a full NTP Client!', mtWarning,
        [mbOK], 0);

      co.SyncFreq:= MinNTPPoolSyncFreq;
      co.SyncFreqUnits:= MinNTPPoolSyncFreqUnits;
    end;

  Problems:= '';
  if ((BaseAndUnitsToValue(co.SyncFreq, co.SyncFreqUnits) div 1000) < 600) then
    Problems:= Problems + '* Update intervals lower than ten minutes are strongly ' +
      'discouraged when synchronizing to public servers, in order to avoid excessive ' +
      'bandwidth costs for the server operators.' + #13#10 + #13#10;
  // if co.Retry < co.SyncFreq then
  // Problems := Problems + '* The retry interval is the time to wait when a server is '+
  // 'down. This should be higher than the normal sync interval, to avoid '+
  // 'creating heavy traffic to a server that can''t handle it.' + #13#10 + #13#10;
  if BaseAndUnitsToValue(co.LostSync, co.LostSyncUnits) <
     (BaseAndUnitsToValue(co.SyncFreq, co.SyncFreqUnits) + (BaseAndUnitsToValue(co.Retry, co.RetryUnits) * 2)) then
    Problems:= Problems + '* The Max Free Run interval is the maximum amount of time ' +
      'that can elapse before we consider the local clock to be out of sync. It is ' +
      'recommended that this be long enough to allow at least two retries.' + #13#10 + #13#10;
  if Problems <> '' then
    if MessageDlg('The following problems were found with your configuration:' + #13#10 + #13#10 + Problems +
      'Do you want to correct these problems automatically?', mtWarning, [mbYes, mbNo], 0) = mrYes then
      begin
        if (BaseAndUnitsToValue(co.SyncFreq, co.SyncFreqUnits) div 1000) < 600 then
          begin
            co.SyncFreq:= 10;
            co.SyncFreqUnits:= ui_Minutes;
          end;
        if BaseAndUnitsToValue(co.LostSync, co.LostSyncUnits) <
           (BaseAndUnitsToValue(co.SyncFreq, co.SyncFreqUnits) + (BaseAndUnitsToValue(co.Retry, co.RetryUnits) * 2)) then
          begin
            ValueToBaseAndUnits((BaseAndUnitsToValue(co.SyncFreq, co.SyncFreqUnits) + (BaseAndUnitsToValue(co.Retry, co.RetryUnits) * 2)),
                                 NewLostSync, NewLostSyncUnits);
            co.LostSync:= Ceil(NewLostSync);
            co.LostSyncUnits:= NewLostSyncUnits;
          end;

        ReadFromObject;
      end;

  co.SetDefaultsAndMinSettings;

  WriteToRegistry;
  if Assigned(tt) then
    WriteToRunning(tt);

  LogMessage('Configuration Updated', log_Verbose);
end;

procedure TfrmOptions.btnHelpClick(Sender: TObject);
begin
  Application.HelpCommand(HELP_CONTEXT, Self.HelpContext);
end;

procedure TfrmOptions.FormCreate(Sender: TObject);
begin
  Hostnames[0]:= edHostname;
  Hostnames[1]:= edHostname1;
  Hostnames[2]:= edHostname2;
  Hostnames[3]:= edHostname3;
  Hostnames[4]:= edHostname4;
  Protocols[0]:= cbxProtocol;
  Protocols[1]:= cbxProtocol1;
  Protocols[2]:= cbxProtocol2;
  Protocols[3]:= cbxProtocol3;
  Protocols[4]:= cbxProtocol4;
  Ports[0]:= edPort;
  Ports[1]:= edPort1;
  Ports[2]:= edPort2;
  Ports[3]:= edPort3;
  Ports[4]:= edPort4;
end;

procedure TfrmOptions.cbxProtocolChange(Sender: TObject);
var i: integer;
begin
  for i:= 0 to MaxServers - 1 do
    if Sender = Protocols[i] then
      Ports[i].Text:= inttostr(DefaultPortForProtocol(TTimeProto(Protocols[i].ItemIndex)));
end;

procedure TfrmOptions.CbxDemoteServersClick(Sender: TObject);
begin
  edDemoteOnErrorCount.Enabled:= CbxDemoteServers.Checked;
end;

procedure TfrmOptions.ViewLogClick(Sender: TObject);
begin
  LogViewForm.ShowForm;
end;

procedure TfrmOptions.cbxAutomaticUpdateChecksEnabledClick(
  Sender: TObject);
begin
  edDaysBetweenUpdateChecks.Enabled:= cbxAutomaticUpdateChecksEnabled.Checked;
end;

procedure TfrmOptions.CheckNowClick(Sender: TObject);
begin
  CheckForUpdates(True);
end;

procedure TfrmOptions.cbxServerClick(Sender: TObject);
begin
  cbxAlwaysProvideTime.Enabled:= cbxServer.Checked;
end;

procedure TfrmOptions.cbxAlwaysProvideTimeClick(Sender: TObject);
begin
  if ReadingFromObject then
    exit;

  if not cbxAlwaysProvideTime.Checked then
    exit;

  if MessageDlg('WARNING! WARNING! WARNING! WARNING!'#13#13+
                'DO NOT enable this option unless you know exactly what you''re doing!!!'#13#13+
                'Enabling this option will allow NetTime to potentially provide incorrect time to other systems!'#13#13+
                'You should only use this option if the system time is being kept accurate from another time source such as a GPS receiver.'#13#13+
                'You should ensure that NetTime isn''t started until the system time has been correctly set and shut it down when the system time may no longer be valid.'#13#13+
                'Have I convinced you to not use this option?', mtWarning, [mbYes, mbNo], 0) = mrYes then
    cbxAlwaysProvideTime.Checked:= False;
end;

end.
