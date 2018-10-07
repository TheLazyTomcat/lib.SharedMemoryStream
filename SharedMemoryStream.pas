{-------------------------------------------------------------------------------

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.

-------------------------------------------------------------------------------}
{===============================================================================

  Shared memory stream

    Simple class that provides a way of accessing shared (system-wide) memory
    using standard stream interface. It is implemented as a wrapper for memory
    mapped files and all access to the memory is interlocked (mutex).
    Sharing of the memory is based on the name - same name (case-insensitive)
    results in access to the same memory. If you left the name empty, a default
    name is used, so all objects with empty name will access the same memory,
    even in different processes.

  ©František Milt 2018-10-08

  Version 1.0b (needs some testing)

  Dependencies:
    AuxTypes           - github.com/ncs-sniper/Lib.AuxTypes  
    StaticMemoryStream - github.com/ncs-sniper/Lib.StaticMemoryStream
    StrRect            - github.com/ncs-sniper/Lib.StrRect

===============================================================================}
unit SharedMemoryStream;

{$IF not(Defined(WINDOWS) or Defined(MSWINDOWS))}
  {$MESSAGE FATAL 'Unsupported operating system.'}
{$IFEND}

{$IFDEF FPC}
  {$MODE ObjFPC}{$H+}
{$ENDIF}

interface

uses
  AuxTypes, StaticMemoryStream;

{===============================================================================
--------------------------------------------------------------------------------
                               TSharedMemoryStream                              
--------------------------------------------------------------------------------
===============================================================================}

{===============================================================================
    TSharedMemoryStream - class declaration
===============================================================================}

type
  TSharedMemoryStream = class(TWritableStaticMemoryStream)
  private
    fName:            String;
    fMappingSynchro:  THandle;
    fMappingObject:   THandle;
  protected
    procedure Lock; virtual;
    procedure Unlock; virtual;
  public
    constructor Create(InitSize: TMemSize; const Name: String = '');
    destructor Destroy; override;
    Function Read(var Buffer; Count: LongInt): LongInt; override;
    Function Write(const Buffer; Count: LongInt): LongInt; override;
    property Name: String read fName;
  end;

implementation

uses
  Windows, SysUtils,
  StrRect;

{===============================================================================
--------------------------------------------------------------------------------
                               TSharedMemoryStream                              
--------------------------------------------------------------------------------
===============================================================================}

const
  SMS_NAME_PREFIX_MAP  = 'sms_map_';
  SMS_NAME_PREFIX_SYNC = 'sms_sync_';

{===============================================================================
    TSharedMemoryStream - class implementation
===============================================================================}

{-------------------------------------------------------------------------------
    TSharedMemoryStream - protected methods
-------------------------------------------------------------------------------}

procedure TSharedMemoryStream.Lock;
begin
WaitForSingleObject(fMappingSynchro,INFINITE);
end;

//------------------------------------------------------------------------------

procedure TSharedMemoryStream.Unlock;
begin
ReleaseMutex(fMappingSynchro);
end;

{-------------------------------------------------------------------------------
    TSharedMemoryStream - public methods
-------------------------------------------------------------------------------}

constructor TSharedMemoryStream.Create(InitSize: TMemSize; const Name: String);
var
  MappingSynchro: THandle;
  MappingObject:  THandle;
  MappedMemory:   Pointer;
begin
// create/open synchronization mutex
MappingSynchro := CreateMutexW(nil,False,PWideChar(StrToWide(SMS_NAME_PREFIX_SYNC + AnsiLowerCase(Name))));
If MappingSynchro = 0 then
  raise Exception.CreateFmt('TSharedMemoryStream.Create: Failed to create mutex (0x%.8x).',[GetLastError]);
// create/open memory mapping
MappingObject := CreateFileMappingW(INVALID_HANDLE_VALUE,nil,PAGE_READWRITE or SEC_COMMIT,DWORD(UInt64(InitSize) shr 32),
  DWORD(InitSize),PWideChar(StrToWide(SMS_NAME_PREFIX_MAP + AnsiLowerCase(Name))));
If MappingObject = 0 then
  raise Exception.CreateFmt('TSharedMemoryStream.Create: Failed to create mapping (0x%.8x).',[GetLastError]);
// map memory
MappedMemory := MapViewOfFile(MappingObject,FILE_MAP_ALL_ACCESS,0,0,InitSize);
If not Assigned(MappedMemory) then
  raise Exception.CreateFmt('TSharedMemoryStream.Create: Failed to map memory (0x%.8x).',[GetLastError]);
// all is well, create the stream on top of the mapped memory
inherited Create(MappedMemory,InitSize);
fName := Name;
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
