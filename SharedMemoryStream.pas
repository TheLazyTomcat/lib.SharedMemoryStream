unit SharedMemoryStream;

{$IFDEF FPC}
  {$MODE ObjFPC}{$H+}
{$ENDIF}

interface

uses
  AuxTypes, StaticMemoryStream;

type
  TSharedMemoryStream = class(TWritableStaticMemoryStream)
  private
    fMappingName:     String;
    fMappingSynchro:  THandle;  
    fMappingObject:   THandle;
  protected
    procedure Lock; virtual;
    procedure Unlock; virtual;
  public
    constructor Create(InitSize: TMemSize; const MappingName: String = '');
    destructor Destroy; override;
    Function Read(var Buffer; Count: LongInt): LongInt; override;
    Function Write(const Buffer; Count: LongInt): LongInt; override;
    property MappingName: String read fMappingName;
  end;

implementation

uses
  Windows, SysUtils,
  StrRect;

const
  SMS_NAME_PREFIX_MAP  = 'sms_map_';
  SMS_NAME_PREFIX_SYNC = 'sms_sync_';

procedure TSharedMemoryStream.Lock;
begin
WaitForSingleObject(fMappingSynchro,INFINITE);
end;

//------------------------------------------------------------------------------

procedure TSharedMemoryStream.Unlock;
begin
ReleaseMutex(fMappingSynchro);
end;

//==============================================================================

constructor TSharedMemoryStream.Create(InitSize: TMemSize; const MappingName: String);
var
  MappingSynchro: THandle;
  MappingObject:  THandle;
  MappedMemory:   Pointer;
begin
// create/open synchronization mutex
MappingSynchro := CreateMutexW(nil,False,PWideChar(StrToWide(SMS_NAME_PREFIX_SYNC + AnsiLowerCase(MappingName))));
If MappingSynchro = 0 then
  raise Exception.CreateFmt('TSharedMemoryStream.Create: Failed to create mutex (0x%.8x).',[GetLastError]);
// create/open memory mapping
MappingObject := CreateFileMappingW(INVALID_HANDLE_VALUE,nil,PAGE_READWRITE or SEC_COMMIT,DWORD(UInt64(InitSize) shr 32),
  DWORD(InitSize),PWideChar(StrToWide(SMS_NAME_PREFIX_MAP + AnsiLowerCase(MappingName))));
If MappingObject = 0 then
  raise Exception.CreateFmt('TSharedMemoryStream.Create: Failed to create mapping (0x%.8x).',[GetLastError]);
// map memory
MappedMemory := MapViewOfFile(MappingObject,FILE_MAP_ALL_ACCESS,0,0,InitSize);
If not Assigned(MappedMemory) then
  raise Exception.CreateFmt('TSharedMemoryStream.Create: Failed to map memory (0x%.8x).',[GetLastError]);
// all is well, create the stream on top of the mapped memory
inherited Create(MappedMemory,InitSize);
fMappingName := MappingName;
fMappingSynchro := MappingSynchro;
fMappingObject := MappingObject;
end;

//------------------------------------------------------------------------------

destructor TSharedMemoryStream.Destroy;
begin
UnmapViewOfFile(Memory);
CloseHandle(fMappingObject);
CloseHandle(fMappingSynchro);
inherited;
end;

//------------------------------------------------------------------------------

Function TSharedMemoryStream.Read(var Buffer; Count: LongInt): LongInt;
begin
Lock;
try
  Result := inherited Read(Buffer,Count);
finally
  Unlock;
end;
end;

//------------------------------------------------------------------------------

Function TSharedMemoryStream.Write(const Buffer; Count: LongInt): LongInt;
begin
Lock;
try
  Result := inherited Write(Buffer,Count);
finally
  Unlock;
end;
end;

end.
