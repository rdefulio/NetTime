{ ************************************************************************

  NetTime is copyrighted by Graham Mainwaring. Permission is hereby
  granted to use, modify, redistribute and create derivative works
  provided this attribution is not removed. I also request that if you
  make any useful changes, please e-mail the diffs to graham@mhn.org
  so that I can include them in an 'official' release.

  Modifications Copyright 2011 - Mark Griffiths

  ************************************************************************ }

unit About;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  ExtCtrls, StdCtrls, Buttons, jpeg, ShellAPI;

type
  TfrmAbout = class(TForm)
    btnOk: TButton;
    Panel1: TPanel;
    Image1: TImage;
    lblVersion: TLabel;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    Label5: TLabel;
    NetTimeWebLink: TLabel;
    procedure FormCreate(Sender: TObject);
    procedure NetTimeWebLinkClick(Sender: TObject);
  private
    { Private declarations }
  end;

var
  frmAbout: TfrmAbout;

procedure DoSplash;
Procedure ShowAboutForm;

implementation

{$R *.DFM}

procedure DoSplash;

var
  fA: TfrmAbout;
  start: longword;

begin
  fA:= TfrmAbout.Create(Application);
  fA.BorderStyle:= bsNone;
  fA.Caption:= '';
  fA.btnOk.Visible:= false;
  fA.Width:= fA.Image1.Width;
  fA.Height:= fA.Image1.Height;
  fA.Show;
  start:= GetTickCount;
  while (GetTickCount - start) < 2500 do
    Application.ProcessMessages;
  fA.Release;
  Application.ProcessMessages;
end;

procedure TfrmAbout.FormCreate(Sender: TObject);

var
  VerSize: cardinal;
  VerHandle: cardinal;
  VerPtr: pointer;
  VerPchar: pchar;
  VerLen: cardinal;

begin
  VerSize:= GetFileVersionInfoSize(pchar(ParamStr(0)), VerHandle);
  if VerSize = 0 then
    exit;
  VerPtr:= pointer(GlobalAlloc(GPTR, VerSize));
  try
    GetFileVersionInfo(pchar(ParamStr(0)), VerHandle, VerSize, VerPtr);
    if not VerQueryValue(VerPtr, '\StringFileInfo\040904E4\FileVersion', pointer(VerPchar), VerLen) then
      exit;
    lblVersion.Caption:= 'Build ' + VerPchar;
  finally
    GlobalFree(cardinal(VerPtr));
  end;
end;

procedure TfrmAbout.NetTimeWebLinkClick(Sender: TObject);
begin
  ShellExecute(0, nil, 'http://www.timesynctool.com', nil, nil, SW_Normal);
end;

Procedure ShowAboutForm;
begin
  if not Assigned(frmAbout) then
    frmAbout:= TfrmAbout.Create(Application);

  if frmAbout.Visible then
    exit;

  frmAbout.ShowModal;
end;

end.
