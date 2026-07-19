; ============================================================
; AI Chat - Inno Setup Installer Script
; ============================================================
; Replace these defines with your actual values

#define MyAppName "AI Chat"
#define MyAppVersion "1.1.2"
#define MyAppPublisher "Lelanka"
#define MyAppURL "https://yourwebsite.com"
#define MyAppExeName "flutter_ai_chat_app_openrouter.exe"
#define MyAppSource "build\windows\x64\runner\Release"

[Setup]
AppId={{244aacd9-93f3-479a-9ceb-efdf849e7c5d}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DisableProgramGroupPage=yes
OutputDir=.\installer_output
OutputBaseFilename=OpenRouter_AI_Chat_Setup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
SetupIconFile=windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#MyAppSource}\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppSource}\*.dll"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs
Source: "{#MyAppSource}\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}\data"