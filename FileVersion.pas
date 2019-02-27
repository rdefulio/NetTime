{ ************************************************************************

  This file is copyrighted 2011, 2012 by Mark Griffiths. Permission is hereby
  granted to use, modify, redistribute and create derivative works
  provided this attribution is not removed.

  ************************************************************************ }

Unit FileVersion;

Interface

Uses Windows, SysUtils, MyStr;

Const
      fvi_CompanyName        = 'CompanyName';
      fvi_FileDescription    = 'FileDescription';
      fvi_FileVersion        = 'FileVersion';
      fvi_InternalName       = 'InternalName';
      fvi_LegalCopyright     = 'LegalCopyright';
      fvi_LegalTradeMarks    = 'LegalTradeMarks';
      fvi_OriginalFilename   = 'OriginalFilename';
      fvi_ProductName        = 'ProductName';
      fvi_ProductVersion     = 'ProductVersion';
      fvi_Comments           = 'Comments';
      fvi_Author             = 'Author';


Function GetFileVersion(FileName: String; var FI: TVSFixedFileInfo): Boolean;
Function GetFileVersionString(FileName: String; VersionInfo: String; var Value: String): Boolean;

Function GetCurrentFileVersionString: String;
Function GetCurrentProductVersion: String;

Implementation

Function GetFileVersion(FileName: String; var FI: TVSFixedFileInfo): Boolean;
var dwInfoSize, dwVerSize, dwWnd: DWORD;
    ptrVerBuf: Pointer;
    PFI: PVSFixedFileInfo;
begin
  Result:= False;

  dwInfoSize:= GetFileVersionInfoSize(PChar(FileName), dwWnd);

  if (dwInfoSize = 0) then
    begin
      exit;
    end
  else
    begin
       GetMem(ptrVerBuf, dwInfoSize);
       try
         if GetFileVersionInfo(PChar(FileName), dwWnd, dwInfoSize, ptrVerBuf) then
           if VerQueryValue(ptrVerBuf, '\', Pointer(PFI), dwVerSize) then
             begin
               FI:= PFI^;
               Result:= True;
             end;
       finally
         FreeMem(ptrVerBuf);
       end;
    end;
end;

Function GetFileVersionString(FileName: String; VersionInfo: String; var Value: String): Boolean;
var dwInfoSize, dwWnd: DWORD;
    ptrVerBuf: Pointer;
    Val: PChar;
    Len: DWord;
    VerBufValue: Pointer;
    VerBufLen: DWord;
    VerValue: String;
begin
  Result:= False;

  dwInfoSize:= GetFileVersionInfoSize(PChar(FileName), dwWnd);

  if (dwInfoSize = 0) then
    begin
      exit;
    end
  else
    begin
       GetMem(ptrVerBuf, dwInfoSize);
       try
         if GetFileVersionInfo(PChar(FileName), dwWnd, dwInfoSize, ptrVerBuf) then
           begin
             if VerQueryValue(ptrVerBuf, '\VarFileInfo\Translation', VerBufValue, VerBufLen) then
               begin
                 VerValue:= IntToHex(LoWord(Integer(VerBufValue^)), 4)+IntToHex(HiWord(Integer(VerBufValue^)), 4);
                 if VerQueryValue(ptrVerBuf, PChar('StringFileInfo\'+VerValue+'\'+VersionInfo), Pointer(Val), Len) then
                   begin
                     Value:= Trim(StrPas(Val));
                     Result:= True;
                   end;
               end;
           end;
       finally
         FreeMem(ptrVerBuf);
       end;
    end;
end;

Function GetCurrentFileVersionString: String;
var FI: TVSFixedFileInfo;
begin
  Result:= '';

  if GetFileVersion(ParamStr(0), FI) then
    begin
      Result:= Format('%d.%d.%d.%d', [HiWord(FI.dwFileVersionMS),
                                      LoWord(FI.dwFileVersionMS),
                                      HiWord(FI.dwFileVersionLS),
                                      LoWord(FI.dwFileVersionLS)]);
    end;
end;

Function GetCurrentProductVersion: String;
begin
  Result:= '';

  GetFileVersionString(ParamStr(0), fvi_ProductVersion, Result);
end;

end.
