{-------------------------------------------------------------------------------

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.

-------------------------------------------------------------------------------}
{===============================================================================

  Shared memory stream

    Provides classes for accessing shared (system-wide) memory, possibly using
    standard stream interface.

    Sharing of the memory is based on the name - same name (case-insensitive)
    results in access to the same memory. For the sake of sanity, it is not
    allowed to use an empty name.

    The actual shared memory is implemented in T(Simple)SharedMemory classes
    and T(Simple)SharedMemoryStream are just stream-interface wrappers around
    them.
    Classes with "simple" in name do not provide any locking, others can be
    locked (methods Lock and Unlock) to prevent data corruption (internally
    implemented via mutex). Simple classes are provided for situations where
    locking is not needed or is implemented by external means.

      NOTE - in Windows OS for non-simple classes, the name of mapping is
             suffixed and is therefore not exactly the same as the name given
             in creation. This is done because the same name is used for named
             mutex used in locking, but Windows do not allow two different
             objects to have the same name.

    In non-simple streams, the methods Read and Write are protected by a lock,
    so it is not necessary to lock the access explicitly.

  Version 1.2.4 (2022-06-06)

  Last change 2022-06-14

  ©2018-2022 František Milt

  Contacts:
    František Milt: frantisek.milt@gmail.com

  Support:
    If you find this code useful, please consider supporting its author(s) by
    making a small donation using the following link(s):

      https://www.paypal.me/FMilt

  Changelog:
    For detailed changelog and history please refer to this git repository:

      github.com/TheLazyTomcat/Lib.SharedMemoryStream

  Dependencies:
    AuxTypes           - github.com/TheLazyTomcat/Lib.AuxTypes
    AuxClasses         - github.com/TheLazyTomcat/Lib.AuxClasses
    StaticMemoryStream - github.com/TheLazyTomcat/Lib.StaticMemoryStream
    StrRect            - github.com/TheLazyTomcat/Lib.StrRect
  * SimpleCPUID        - github.com/TheLazyTomcat/Lib.SimpleCPUID
  * InterlockedOps     - github.com/TheLazyTomcat/Lib.InterlockedOps
  * SimpleFutex        - github.com/TheLazyTomcat/Lib.SimpleFutex

  Libraries SimpleFutex, InterlockedOps and SimpleCPUID are required only when
  compiling for Linux operating system.

  SimpleCPUID might not be required, depending on defined symbols in library
  InterlockedOps.

===============================================================================}
unit SharedMemoryStream;

{$IF defined(CPU64) or defined(CPU64BITS)}
  {$DEFINE CPU64bit}
{$ELSEIF defined(CPU16)}
  {$MESSAGE FATAL '16bit CPU not supported'}
{$ELSE}
  {$DEFINE CPU32bit}
{$IFEND}

{$IF Defined(WINDOWS) or Defined(MSWINDOWS)}
  {$DEFINE Windows}
{$ELSEIF Defined(LINUX) and Defined(FPC)}
  {$DEFINE Linux}
{$ELSE}
  {$MESSAGE FATAL 'Unsupported operating system.'}
{$IFEND}

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$MODESWITCH DuplicateLocals+}
  {$DEFINE FPC_DisableWarns}
  {$MACRO ON}
{$ENDIF}
{$H+}

interface

uses
  SysUtils, Classes, {$IFDEF Linux}baseunix,{$ENDIF}
  AuxTypes, AuxClasses, StaticMemoryStream{$IFDEF Linux}, SimpleFutex{$ENDIF};

{===============================================================================
    Library-specific exceptions
===============================================================================}
type
  ESHMSException = class(Exception);

  ESHMSInvalidValue         = class(ESHMSException);
  ESHMSMutexCreationError   = class(ESHMSException);
  ESHMSMappingCreationError = class(ESHMSException);
  ESHMSMappingTruncateError = class(ESHMSException);  // linux only
  ESHMSMemoryMappingError   = class(ESHMSException);

  ESHMSLockError   = class(ESHMSException);
  ESHMSUnlockError = class(ESHMSException);

{===============================================================================
--------------------------------------------------------------------------------
                               TSimpleSharedMemory
--------------------------------------------------------------------------------
===============================================================================}
{$IFDEF Linux}
type
  TSharedMemoryHeader = record
    RefLock:      TFutex;
    RefCount:     Int32;
    Synchronizer: pthread_mutex_t;
  end;
  PSharedMemoryHeader = ^TSharedMemoryHeader;
{$ENDIF}

{===============================================================================
    TSimpleSharedMemory - class declaration
===============================================================================}
type
  TSimpleSharedMemory = class(TCustomObject)
  protected
    fName:        String;
    fMemory:      Pointer;
    fSize:        TMemSize;
  {$IFDEF Windows}
    fMappingObj:  THandle;
    class Function GetMappingSuffix: String; virtual;
  {$ELSE}
    fMemoryBase:  Pointer;
    fFullSize:    TMemSize;
    fHeaderPtr:   PSharedMemoryHeader;
    procedure InitializeMutex; virtual;
    procedure FinalizeMutex; virtual;
    Function TryInitialize: Boolean; virtual;
  {$ENDIF}
    procedure Initialize; virtual;
    procedure Finalize; virtual;
    class Function RectifyName(const Name: String): String; virtual;
  public
    constructor Create(InitSize: TMemSize; const Name: String);
    destructor Destroy; override;
    property Name: String read fName;
    property Memory: Pointer read fMemory;
    property Size: TMemSize read fSize;
  end;

{===============================================================================
--------------------------------------------------------------------------------
                                 TSharedMemory
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TSharedMemory - class declaration
===============================================================================}
type
  TSharedMemory = class(TSimpleSharedMemory)
  protected
  {$IFDEF Windows}
    fMappingSync: THandle;
    class Function GetMappingSuffix: String; override;
    procedure Initialize; override;
    procedure Finalize; override;
  {$ELSE}
    procedure InitializeMutex; override;
    procedure FinalizeMutex; override;
  {$ENDIF}
  public
    procedure Lock; virtual;
    procedure Unlock; virtual;
  end;

{===============================================================================
--------------------------------------------------------------------------------
                            TSimpleSharedMemoryStream
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TSimpleSharedMemoryStream - class declaration
===============================================================================}
type
  TSimpleSharedMemoryStream = class(TWritableStaticMemoryStream)
  protected
    fSharedMemory:  TSimpleSharedMemory;
    Function GetName: String; virtual;
    class Function GetSharedMemoryInstance(InitSize: TMemSize; const Name: String): TSimpleSharedMemory; virtual;
  public
    constructor Create(InitSize: TMemSize; const Name: String);
    destructor Destroy; override;
    Function Read(var Buffer; Count: LongInt): LongInt; override;
    Function Write(const Buffer; Count: LongInt): LongInt; override;
    property Name: String read GetName;
  end;

{===============================================================================
--------------------------------------------------------------------------------
                              TSharedMemoryStream
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TSharedMemoryStream - class declaration
===============================================================================}
type
  TSharedMemoryStream = class(TSimpleSharedMemoryStream)
  protected
    class Function GetSharedMemoryInstance(InitSize: TMemSize; const Name: String): TSimpleSharedMemory; override;
  public
    procedure Lock; virtual;
    procedure Unlock; virtual;
    Function Read(var Buffer; Count: LongInt): LongInt; override;
    Function Write(const Buffer; Count: LongInt): LongInt; override;
  end;

implementation

uses
  {$IFDEF Windows}Windows,{$ELSE}unixtype, StrUtils,{$ENDIF}
  StrRect;

{$IFDEF Linux}
  {$LINKLIB libc}
  {$LINKLIB librt}
  {$LINKLIB pthread}
{$ENDIF}

{$IFDEF FPC_DisableWarns}
  {$DEFINE FPCDWM}
  {$DEFINE W4055:={$WARN 4055 OFF}} // Conversion between ordinals and pointers is not portable
{$ENDIF}

{===============================================================================
--------------------------------------------------------------------------------
                               TSimpleSharedMemory
--------------------------------------------------------------------------------
===============================================================================}
{$IFDEF Windows}

const
{
  Do not change to prefixes! It would interfere with system prefixes added to
  the name by user.

  Both suffixes MUST be the same length.
}
  SHMS_NAME_SUFFIX_SECT = '@shms_sect'; // section :P
  SHMS_NAME_SUFFIX_SYNC = '@shms_sync';

  SHMS_NAME_SUFFIX_LEN = Length(SHMS_NAME_SUFFIX_SECT);

{$IF not Declared(UNICODE_STRING_MAX_CHARS)}
  UNICODE_STRING_MAX_CHARS = 32767;
{$IFEND}

{$ELSE}

Function errno_ptr: pcint; cdecl; external name '__errno_location';
Function sched_yield: cint; cdecl; external;
Function close(fd: cint): cint; cdecl; external;
Function ftruncate(fd: cint; length: off_t): cint; cdecl; external;
Function mmap(addr: Pointer; length: size_t; prot,flags,fd: cint; offset: off_t): Pointer; cdecl; external;
Function munmap(addr: Pointer; length: size_t): cint; cdecl; external;

type
  pthread_mutexattr_p = ^pthread_mutexattr_t;
  pthread_mutex_p = ^pthread_mutex_t;

const
  PTHREAD_PROCESS_SHARED  = 1;
  PTHREAD_MUTEX_RECURSIVE = 1;

Function pthread_mutexattr_init(attr: pthread_mutexattr_p): cint; cdecl; external;
Function pthread_mutexattr_destroy(attr: pthread_mutexattr_p): cint; cdecl; external;
Function pthread_mutexattr_setpshared(attr: pthread_mutexattr_p; pshared: cint): cint; cdecl; external;
Function pthread_mutexattr_settype(attr: pthread_mutexattr_p; _type: cint): cint; cdecl; external;

Function pthread_mutex_init(mutex: pthread_mutex_p; attr: pthread_mutexattr_p): cint; cdecl; external;
Function pthread_mutex_destroy(mutex: pthread_mutex_p): cint; cdecl; external;
Function pthread_mutex_lock(mutex: pthread_mutex_p): cint; cdecl; external;
Function pthread_mutex_unlock(mutex: pthread_mutex_p): cint; cdecl; external;

Function shm_open(name: pchar; oflag: cint; mode: mode_t): cint; cdecl; external;
Function shm_unlink(name: pchar): cint; cdecl; external;

threadvar
  ThrErrorCode: cInt;

Function ErrChk(ErrorCode: cInt): Boolean;
begin
Result := ErrorCode = 0;
If Result then
  ThrErrorCode := 0
else
  ThrErrorCode := ErrorCode;
end;

{$ENDIF}

{===============================================================================
    TSimpleSharedMemory - class implementation
===============================================================================}
{-------------------------------------------------------------------------------
    TSimpleSharedMemory - protected methods
-------------------------------------------------------------------------------}

{$IFDEF Windows}

class Function TSimpleSharedMemory.GetMappingSuffix: String;
begin
Result := '';
end;

//------------------------------------------------------------------------------

procedure TSimpleSharedMemory.Initialize;
begin
// create/open memory mapping
fMappingObj := CreateFileMappingW(INVALID_HANDLE_VALUE,nil,PAGE_READWRITE or SEC_COMMIT,DWORD(UInt64(fSize) shr 32),
                                  DWORD(fSize),PWideChar(StrToWide(fName + GetMappingSuffix)));
If fMappingObj = 0 then
  raise ESHMSMappingCreationError.CreateFmt('TSimpleSharedMemory.Initialize: Failed to create mapping (%d).',[GetLastError]);
// map memory
fMemory := MapViewOfFile(fMappingObj,FILE_MAP_ALL_ACCESS,0,0,fSize);
If not Assigned(fMemory) then
  raise ESHMSMemoryMappingError.CreateFmt('TSimpleSharedMemory.Initialize: Failed to map memory (%d).',[GetLastError]);
end;

//------------------------------------------------------------------------------

procedure TSimpleSharedMemory.Finalize;
begin
UnmapViewOfFile(Memory);
CloseHandle(fMappingObj);
end;

//------------------------------------------------------------------------------

class Function TSimpleSharedMemory.RectifyName(const Name: String): String;
var
  i,Cnt:  Integer;
begin
{
  Convert to lower case and limit the length while accounting for suffixes.
  There can be exactly one backslash (separating namespace prefix), replace
  other backslashes by underscores.
}
Result := AnsiLowerCase(Name);
If (Length(Result) + SHMS_NAME_SUFFIX_LEN) > UNICODE_STRING_MAX_CHARS then
  SetLength(Result,UNICODE_STRING_MAX_CHARS - SHMS_NAME_SUFFIX_LEN);
Cnt := 0;
For i := 1 to Length(Result) do
  If Result[i] = '\' then
    begin
      If Cnt > 0 then
        Result[i] := '_';
      Inc(Cnt);
    end;
end;

{$ELSE}//=======================================================================

procedure TSimpleSharedMemory.InitializeMutex;
begin
// do nothing
end;

//------------------------------------------------------------------------------

procedure TSimpleSharedMemory.FinalizeMutex;
begin
// do nothing
end;

//------------------------------------------------------------------------------

Function TSimpleSharedMemory.TryInitialize: Boolean;
var
  MappingObj: cint;
begin
Result := False;
// add space for header
fFullSize := (TMemSize(SizeOf(TSharedMemoryHeader) + 127) and not TMemSize(127)) + fSize;
// create/open mapping
MappingObj := shm_open(PChar(StrToSys(fName)),O_CREAT or O_RDWR,S_IRWXU);
If MappingObj >= 0 then
  try
    If ftruncate(MappingObj,off_t(fFullSize)) < 0 then
      raise ESHMSMappingTruncateError.CreateFmt('TSimpleSharedMemory.Initialize: Failed to truncate mapping (%d).',[errno_ptr^]);
    // map file into memory
    fMemoryBase := mmap(nil,size_t(fFullSize),PROT_READ or PROT_WRITE,MAP_SHARED,MappingObj,0);
    If Assigned(fMemoryBase) and (fMemoryBase <> Pointer(-1){MAP_FAILED}) then
      begin
        fHeaderPtr := fMemoryBase;
      {$IFDEF FPCDWM}{$PUSH}W4055{$ENDIF}
        fMemory := Pointer(PtrUInt(fMemoryBase) + (PtrUInt(SizeOf(TSharedMemoryHeader) + 127) and not PtrUInt(127)));
      {$IFDEF FPCDWM}{$POP}{$ENDIF}
        SimpleMutexLock(fHeaderPtr^.RefLock);
        try
          If fHeaderPtr^.RefCount = 0 then
            begin
            {
              This is the first time the mapping is accessed - create mutex and
              set reference count to 1.
            }
              InitializeMutex;
              fHeaderPtr^.RefCount := 1;
              Result := True
            end
          else If fHeaderPtr^.RefCount > 0 then
            begin
              // The mapping and mutex is set up, only increase reference count.
              Inc(fHeaderPtr^.RefCount);
              Result := True;
            end
        {
          The mapping was unlinked and mutex destroyed somewhere between
          shm_open and SimpleFutexLock - drop current mapping and start mapping
          again from scratch.
        }
          else munmap(fMemoryBase,size_t(fFullSize));
        finally
          SimpleMutexUnlock(fHeaderPtr^.RefLock);
        end;
      end
    else raise ESHMSMemoryMappingError.CreateFmt('TSimpleSharedMemory.Initialize: Failed to map memory (%d).',[errno_ptr^]);
  finally
    close(MappingObj);
  end
else raise ESHMSMappingCreationError.CreateFmt('TSimpleSharedMemory.Initialize: Failed to create mapping (%d).',[errno_ptr^]);
end;

//------------------------------------------------------------------------------

procedure TSimpleSharedMemory.Initialize;
begin
while not TryInitialize do
  sched_yield;
end;

//------------------------------------------------------------------------------

procedure TSimpleSharedMemory.Finalize;
begin
{
  If there was exception in the constructor, the header pointer might not be
  set by this point.
}
If Assigned(fHeaderPtr) then
  begin
    SimpleMutexLock(fHeaderPtr^.RefLock);
    try
      If fHeaderPtr^.RefCount = 0 then
        begin
        {
          Zero should be possible only if the initialization failed when
          creating the mutex.
          Unlink the mapping but do not destroy mutex (it should not exist).
        }
          fHeaderPtr^.RefCount := -1;
          shm_unlink(PChar(StrToSys(fName)));
        end
      else If fHeaderPtr^.RefCount = 1 then
        begin
        {
          This is the last instance, destroy mutex and unlink the mapping.
          Set reference counter to -1 to indicate it is being destroyed.
        }
          fHeaderPtr^.RefCount := -1;
          // destroy mutex
          FinalizeMutex;
          // unlink mapping (ignore errors)
          shm_unlink(PChar(StrToSys(fName)));
        end
      else If fHeaderPtr^.RefCount > 1 then
        Dec(fHeaderPtr^.RefCount);
      {
        Negative value means the mapping is already being destroyed elsewhere,
        so do nothing.
      }
    finally
      SimpleMutexUnlock(fHeaderPtr^.RefLock);
    end;
  end;
// unmapping is done in any case...
If Assigned(fMemoryBase) and (fMemoryBase <> Pointer(-1)) then
  munmap(fMemoryBase,size_t(fFullSize));
end;

//------------------------------------------------------------------------------

class Function TSimpleSharedMemory.RectifyName(const Name: String): String;
var
  i:  Integer;
begin
{
  The name must start with forward slash and must not contain any more fwd.
  slashes.
  Check if there is leading slash and add it when isn't, replace other slashes
  with underscores and convert to lower case. Also limit the length to NAME_MAX
  characters.
}
If not AnsiStartsText('/',Name) then
  Result := AnsiLowerCase('/' + Name)
else
  Result := AnsiLowerCase(Name);
If Length(Result) > NAME_MAX then
  SetLength(Result,NAME_MAX);
For i := 2 to Length(Result) do
  If Result[i] = '/' then
    Result[i] := '_';
end;

{$ENDIF}

{-------------------------------------------------------------------------------
    TSimpleSharedMemory - public methods
-------------------------------------------------------------------------------}

constructor TSimpleSharedMemory.Create(InitSize: TMemSize; const Name: String);
begin
inherited Create;
fName := RectifyName(Name);
If Length(fName) <= 0 then
  raise ESHMSInvalidValue.Create('TSimpleSharedMemory.Create: Empty name not allowed.');
fSize := InitSize;
Initialize;
end;

//------------------------------------------------------------------------------

destructor TSimpleSharedMemory.Destroy;
begin
Finalize;
inherited;
end;

{===============================================================================
--------------------------------------------------------------------------------
                                 TSharedMemory
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TSharedMemory - class declaration
===============================================================================}
{-------------------------------------------------------------------------------
    TSharedMemory - protected methods
-------------------------------------------------------------------------------}

{$IFDEF Windows}

class Function TSharedMemory.GetMappingSuffix: String;
begin
// do not call inherited code
Result := SHMS_NAME_SUFFIX_SECT;
end;

//------------------------------------------------------------------------------

procedure TSharedMemory.Initialize;
begin
// create/open synchronization mutex
fMappingSync := CreateMutexW(nil,False,PWideChar(StrToWide(fName + SHMS_NAME_SUFFIX_SYNC)));
If fMappingSync = 0 then
  raise ESHMSMutexCreationError.CreateFmt('TSharedMemory.Initialize: Failed to create mutex (%d).',[GetLastError]);
inherited;
end;

//------------------------------------------------------------------------------

procedure TSharedMemory.Finalize;
begin
inherited;
CloseHandle(fMappingSync);
end;

{$ELSE}
//------------------------------------------------------------------------------

procedure TSharedMemory.InitializeMutex;
var
  MutexAttr:  pthread_mutexattr_t;
begin
If ErrChk(pthread_mutexattr_init(@MutexAttr)) then
  try
    If not ErrChk(pthread_mutexattr_setpshared(@MutexAttr,PTHREAD_PROCESS_SHARED)) then
      raise ESHMSMutexCreationError.CreateFmt('TSharedMemory.InitializeMutex: Failed to set mutex attribute pshared (%d).',[ThrErrorCode]);
    If not ErrChk(pthread_mutexattr_settype(@MutexAttr,PTHREAD_MUTEX_RECURSIVE)) then
      raise ESHMSMutexCreationError.CreateFmt('TSharedMemory.InitializeMutex: Failed to set mutex attribute type (%d).',[ThrErrorCode]);
    If not ErrChk(pthread_mutex_init(Addr(fHeaderPtr^.Synchronizer),@MutexAttr)) then
      raise ESHMSMutexCreationError.CreateFmt('TSharedMemory.InitializeMutex: Failed to init mutex (%d).',[ThrErrorCode]);
  finally
    pthread_mutexattr_destroy(@MutexAttr);
  end
else raise ESHMSMutexCreationError.CreateFmt('TSharedMemory.InitializeMutex: Failed to init mutex attributes (%d).',[ThrErrorCode]);
end;

//------------------------------------------------------------------------------

procedure TSharedMemory.FinalizeMutex;
begin
// ignore errors
pthread_mutex_destroy(Addr(fHeaderPtr^.Synchronizer));
end;

{$ENDIF}

{-------------------------------------------------------------------------------
    TSharedMemory - public methods
-------------------------------------------------------------------------------}

procedure TSharedMemory.Lock;
begin
{$IFDEF Windows}
If not(WaitForSingleObject(fMappingSync,INFINITE) in [WAIT_ABANDONED,WAIT_OBJECT_0]) then
  raise ESHMSLockError.Create('TSharedMemory.Lock: Failed to lock.');
{$ELSE}
If not ErrChk(pthread_mutex_lock(Addr(fHeaderPtr^.Synchronizer))) then
  raise ESHMSLockError.CreateFmt('TSharedMemory.Lock: Failed to lock (%d).',[ThrErrorCode]);
{$ENDIF}
end;

//------------------------------------------------------------------------------

procedure TSharedMemory.Unlock;
begin
{$IFDEF Windows}
If not ReleaseMutex(fMappingSync) then
  raise ESHMSUnlockError.CreateFmt('TSharedMemory.Unlock: Failed to unlock (%d).',[GetLastError]);
{$ELSE}
If not ErrChk(pthread_mutex_unlock(Addr(fHeaderPtr^.Synchronizer))) then
  raise ESHMSUnlockError.CreateFmt('TSharedMemory.Unlock: Failed to unlock (%d).',[ThrErrorCode]);
{$ENDIF}
end;


{===============================================================================
--------------------------------------------------------------------------------
                            TSimpleSharedMemoryStream
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TSimpleSharedMemoryStream - class implementation
===============================================================================}
{-------------------------------------------------------------------------------
    TSharedMemoryStream - protected methods
-------------------------------------------------------------------------------}

Function TSimpleSharedMemoryStream.GetName: String;
begin
Result := fSharedMemory.Name;
end;

//------------------------------------------------------------------------------

class Function TSimpleSharedMemoryStream.GetSharedMemoryInstance(InitSize: TMemSize; const Name: String): TSimpleSharedMemory;
begin
Result := TSimpleSharedMemory.Create(InitSize,Name);
end;

{-------------------------------------------------------------------------------
    TSharedMemoryStream - public methods
-------------------------------------------------------------------------------}

constructor TSimpleSharedMemoryStream.Create(InitSize: TMemSize; const Name: String);
var
  SharedMemory: TSimpleSharedMemory;
begin
SharedMemory := GetSharedMemoryInstance(InitSize,Name);
try
  inherited Create(SharedMemory.Memory,SharedMemory.Size);
except
  // in case inherited constructor fails
  FreeAndNil(SharedMemory);
  raise;
end;
fSharedMemory := SharedMemory;
end;

//------------------------------------------------------------------------------

destructor TSimpleSharedMemoryStream.Destroy;
begin
FreeAndNil(fSharedMemory);
inherited;
end;

//------------------------------------------------------------------------------

Function TSimpleSharedMemoryStream.Read(var Buffer; Count: LongInt): LongInt;
begin
Result := inherited Read(Buffer,Count);
end;

//------------------------------------------------------------------------------

Function TSimpleSharedMemoryStream.Write(const Buffer; Count: LongInt): LongInt;
begin
Result := inherited Write(Buffer,Count);
end;


{===============================================================================
--------------------------------------------------------------------------------
                              TSharedMemoryStream
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TSharedMemoryStream - class declaration
===============================================================================}
{-------------------------------------------------------------------------------
    TSharedMemoryStream - protected methods
-------------------------------------------------------------------------------}

class Function TSharedMemoryStream.GetSharedMemoryInstance(InitSize: TMemSize; const Name: String): TSimpleSharedMemory;
begin
// do not call inherited code
Result := TSharedMemory.Create(InitSize,Name);
end;

{-------------------------------------------------------------------------------
    TSharedMemoryStream - public methods
-------------------------------------------------------------------------------}

procedure TSharedMemoryStream.Lock;
begin
TSharedMemory(fSharedMemory).Lock;
end;

//------------------------------------------------------------------------------

procedure TSharedMemoryStream.Unlock;
begin
TSharedMemory(fSharedMemory).Unlock;
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

