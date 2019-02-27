object LogViewForm: TLogViewForm
  Left = 247
  Top = 257
  AutoScroll = False
  BorderIcons = [biSystemMenu, biMaximize]
  Caption = 'NetTime Log Viewer'
  ClientHeight = 372
  ClientWidth = 576
  Color = clBtnFace
  Constraints.MinHeight = 300
  Constraints.MinWidth = 300
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'MS Sans Serif'
  Font.Style = []
  OldCreateOrder = False
  Position = poScreenCenter
  DesignSize = (
    576
    372)
  PixelsPerInch = 96
  TextHeight = 13
  object Log: TMemo
    Left = 8
    Top = 8
    Width = 561
    Height = 325
    Anchors = [akLeft, akTop, akRight, akBottom]
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -11
    Font.Name = 'Courier New'
    Font.Style = []
    ParentFont = False
    ReadOnly = True
    ScrollBars = ssBoth
    TabOrder = 0
  end
  object Close: TButton
    Left = 248
    Top = 340
    Width = 75
    Height = 25
    Anchors = [akBottom]
    Caption = 'Close'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -11
    Font.Name = 'Arial'
    Font.Style = []
    ParentFont = False
    TabOrder = 1
    OnClick = CloseClick
  end
  object Timer1: TTimer
    Interval = 500
    OnTimer = Timer1Timer
    Left = 16
    Top = 340
  end
end
