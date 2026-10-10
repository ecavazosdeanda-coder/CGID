[Code]

#ifndef MyAppVersion
  #define MyAppVersion "2.0.0-rc.2"
#endif

[Setup]
AppId={{AC8B9840-0542-4261-9A17-4CB4A8DE84F4}
AppName=CGID
AppVersion={#MyAppVersion}
AppPublisher=Eustolio Cavazos de Anda
DefaultDirName={localappdata}\Programs\CGID
DefaultGroupName=CGID
PrivilegesRequired=lowest
OutputDir=..\release
OutputBaseFilename=CGID_{#MyAppVersion}_Windows_x64_unsigned_Setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\cgid.exe
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\CGID"; Filename: "{app}\cgid.exe"
Name: "{autodesktop}\CGID"; Filename: "{app}\cgid.exe"

[Run]
Filename: "{app}\cgid.exe"; Description: "Abrir CGID"; Flags: nowait postinstall skipifsilent
