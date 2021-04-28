{-------------------------------------------------------------------------------

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.

-------------------------------------------------------------------------------}
{===============================================================================

  Shared memory stream

    Simple class that provides a way of accessing shared (system-wide) memory
    using standard stream interface.
    The actual shared memory is implemented in TSharedMemory class and
    TSharedMemoryStream is just a stream-interface wrapper around it.

    For the sake of data integrity, all access to shared memory in the stream
    is protected by locks (mutex).

    Sharing of the memory is based on the name - same name (case-insensitive)
    results in access to the same memory. If you leave the name empty, a default
    name is used, so all objects with empty name will access the same memory,
    even in different processes.

  Version 1.1 (2021-04-29)

  Last change 2021-04-29

  ©2018-2021 František Milt

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
    StaticMemoryStream - github.com/TheLazyTomcat/Lib.StaticMemoryStream
    StrRect            - github.com/TheLazyTomcat/Lib.StrRect

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
  {$DEFINE FPC_DisableWarns}
  {$MACRO ON}
{$ENDIF}
{$H+}

interface

uses
  SysUtils, {$IFDEF Linux}baseunix,{$ENDIF}
  AuxTypes, StaticMemoryStream;

type
  ESHMSException = class(Exception);

  ESHMSSystemError = class(ESHMSException);

{===============================================================================
--------------------------------------------------------------------------------
                                 TSharedMemory
--------------------------------------------------------------------------------
===============================================================================}
{$IFDEF Linux}
type
  TSharedMemoryFooter = record
    Synchronizer: pthread_mutex_t;
    RefCount:     Integer;
  end;
  PSharedMemoryFooter = ^tSharedMemoryFooter;
{$ENDIF}

{===============================================================================
    TSharedMemory - class declaration
===============================================================================}
type
  TSharedMemory = class(TObject)
  protected
    fName:        String;
    fMemory:      Pointer;
    fSize:        TMemSize;
  {$IFDEF Windows}
    fMappingObj:  THandle;
    fMappingSync: THandle;
  {$ELSE}
    fFullSize:    TMemSize;
    fFooterPtr:   PSharedMemoryFooter;
  {$ENDIF}
    procedure InitializeLock; virtual;
    procedure FinalizeLock; virtual;
    procedure Initialize; virtual;
    procedure Finalize; virtual;
    class Function RectifyName(const Name: String): String; virtual;
  public
    constructor Create(InitSize: TMemSize; const Name: String);
    destructor Destroy; override;
    procedure Lock; virtual;
    procedure Unlock; virtual;
    property Name: String read fName;
    property Memory: Pointer read fMemory;
    property Size: TMemSize read fSize;
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
  TSharedMemoryStream = class(TWritableStaticMemoryStream)
  protected
    fSharedMemory:  TSharedMemory;
    Function GetName: String; virtual;
  public
    constructor Create(InitSize: TMemSize; const Name: String = '');
    destructor Destroy; override;
    Function Read(var Buffer; Count: LongInt): LongInt; override;
    Function Write(const Buffer; Count: LongInt): LongInt; override;
    procedure Lock; virtual;
    procedure Unlock; virtual;
    property Name: String read GetName;
  end;

implementation

uses
  {$IFDEF Windows}Windows,{$ELSE}unixtype,{$ENDIF} StrUtils,
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
                                 TSharedMemory
--------------------------------------------------------------------------------
===============================================================================}
{$IFDEF Windows}

const
  SHMS_NAME_SUFFIX_MAP  = '_shms_map';
  SHMS_NAME_SUFFIX_SYNC = '_shms_sync';

{$ELSE}

Function errno_ptr: pcint; cdecl; external name '__errno_location';
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

{$ENDIF}

{===============================================================================
    TSharedMemory - class implementation
===============================================================================}
{-------------------------------------------------------------------------------
    TSharedMemory - protected methods
-------------------------------------------------------------------------------}

procedure TSharedMemory.InitializeLock;
{$IFDEF Windows}
begin
fMappingSync := CreateMutexW(nil,False,PWideChar(StrToWide(fName + SHMS_NAME_SUFFIX_SYNC)));
If fMappingSync = 0 then
  raise ESHMSSystemError.CreateFmt('TSharedMemory.InitializeLock: Failed to create mutex (0x%.8x).',[GetLastError]);
{$ELSE}
var
  MutexAttr:  pthread_mutexattr_t;
begin
If pthread_mutexattr_init(@MutexAttr) = 0 then
  try
    If pthread_mutexattr_setpshared(@MutexAttr,PTHREAD_PROCESS_SHARED) <> 0 then
      raise ESHMSSystemError.CreateFmt('TSharedMemory.InitializeLock: Failed to set mutex attribute pshared (%d).',[errno_ptr^]);
    If pthread_mutexattr_settype(@MutexAttr,PTHREAD_MUTEX_RECURSIVE) <> 0 then
      raise ESHMSSystemError.CreateFmt('TSharedMemory.InitializeLock: Failed to set mutex attribute type (%d).',[errno_ptr^]);
    If pthread_mutex_init(Addr(fFooterPtr^.Synchronizer),@MutexAttr) <> 0 then
      raise ESHMSSystemError.CreateFmt('TSharedMemory.InitializeLock: Failed to init mutex (%d).',[errno_ptr^]);
  finally
    pthread_mutexattr_destroy(@MutexAttr);
  end
else raise ESHMSSystemError.CreateFmt('TSharedMemory.InitializeLock: Failed to init mutex attributes (%d).',[errno_ptr^]);
{$ENDIF}
end;

//------------------------------------------------------------------------------

procedure TSharedMemory.FinalizeLock;
begin
{$IFDEF Windows}
CloseHandle(fMappingSync);
{$ELSE}
pthread_mutex_destroy(Addr(fFooterPtr^.Synchronizer));
{$ENDIF}
end;

//------------------------------------------------------------------------------

procedure TSharedMemory.Initialize;
{$IFDEF Windows}
begin
// create/open memory mapping
fMappingObj := CreateFileMappingW(INVALID_HANDLE_VALUE,nil,PAGE_READWRITE or SEC_COMMIT,DWORD(UInt64(fSize) shr 32),
                                  DWORD(fSize),PWideChar(StrToWide(fName + SHMS_NAME_SUFFIX_MAP)));
If fMappingObj = 0 then
  raise ESHMSSystemError.CreateFmt('TSharedMemory.Initialize: Failed to create mapping (0x%.8x).',[GetLastError]);
// map memory
fMemory := MapViewOfFile(fMappingObj,FILE_MAP_ALL_ACCESS,0,0,fSize);
If not Assigned(fMemory) then
  raise ESHMSSystemError.CreateFmt('TSharedMemory.Initialize: Failed to map memory (0x%.8x).',[GetLastError]);
InitializeLock;
{$ELSE}
var
  MappingObj: cint;
begin
// add aligned space for footer
fFullSize := ((fSize + 15) and not TMemSize(15)) + SizeOf(TSharedMemoryFooter);
// create/open mapping
MappingObj := shm_open(PChar(StrToSys(fName)),O_CREAT or O_RDWR,S_IRWXU);
If MappingObj >= 0 then
  try
    If ftruncate(MappingObj,off_t(fFullSize)) < 0 then
      raise ESHMSSystemError.CreateFmt('TSharedMemory.Initialize: Failed to truncate mapping (%d).',[errno_ptr^]);
    // map file into memory
    fMemory := mmap(nil,size_t(fFullSize),PROT_READ or PROT_WRITE,MAP_SHARED,MappingObj,0);
    If Assigned(fMemory) and (Memory <> Pointer(-1)) then
      begin
      {$IFDEF FPCDWM}{$PUSH}W4055{$ENDIF}
        fFooterPtr := Pointer(PtrUInt(fMemory) + PtrUInt((fSize + 15) and not TMemSize(15)));
      {$IFDEF FPCDWM}{$POP}{$ENDIF}
        If InterlockedIncrement(fFooterPtr^.RefCount) <= 1 then
          InitializeLock;
      end
    else raise ESHMSSystemError.CreateFmt('TSharedMemory.Initialize: Failed to map memory (%d).',[errno_ptr^]);
  finally
    close(MappingObj);
  end
else raise ESHMSSystemError.CreateFmt('TSharedMemory.Initialize: Failed to create mapping (%d).',[errno_ptr^]);
{$ENDIF}
end;

//------------------------------------------------------------------------------

procedure TSharedMemory.Finalize;
begin
{$IFDEF Windows}
FinalizeLock;
UnmapViewOfFile(Memory);
CloseHandle(fMappingObj);
{$ELSE}
If Assigned(fFooterPtr) then
  If InterlockedDecrement(fFooterPtr^.RefCount) <= 0 then
    begin
      FinalizeLock;
      // unlink mapping
      shm_unlink(PChar(StrToSys(fName)));
    end;
If Assigned(fMemory) and (Memory <> Pointer(-1)) then
  munmap(fMemory,size_t(fFullSize));
{$ENDIF}
end;

//------------------------------------------------------------------------------

class Function TSharedMemory.RectifyName(const Name: String): String;
{$IFDEF Windows}
var
  Start:  TStrSize;
  i:      Integer;
begin
{
  The name cannot contain backslash, unless it separates Local or Global prefix.
  Replace backslashes by underscores and convert to lower case.
}
If AnsiStartsText('Local\',Name) then
  Start := 7
else If AnsiStartsText('Global\',Name) then
  Start := 8
else
  Start := 1;
Result := Copy(Name,1,Pred(Start)) + AnsiLowerCase(Copy(Name,Start,Length(Name)));
For i := Start to Length(Result) do
  If Result[i] = '\' then
    Result[i] := '_';
{$ELSE}
var
  i:  Integer;
begin
{
  The name must start with forward slash and must not contain any more fwd.
  slashes.
  Check if there is leading slash and add it when isn't, replace other slashes
  by underscores and convert to lower case. Also limit the length to NAME_MAX
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
{$ENDIF}
end;

{-------------------------------------------------------------------------------
    TSharedMemory - public methods
-------------------------------------------------------------------------------}

constructor TSharedMemory.Create(InitSize: TMemSize; const Name: String);
begin
inherited Create;
fName := RectifyName(Name);
fSize := InitSize;
Initialize;
end;

//------------------------------------------------------------------------------

destructor TSharedMemory.Destroy;
begin
Finalize;
inherited;
end;

//------------------------------------------------------------------------------

procedure TSharedMemory.Lock;
begin
{$IFDEF Windows}
If not(WaitForSingleObject(fMappingSync,INFINITE) in [WAIT_ABANDONED,WAIT_OBJECT_0]) then
  raise ESHMSSystemError.Create('TSharedMemory.Lock: Failed to lock.');  ;
{$ELSE}
If pthread_mutex_lock(Addr(fFooterPtr^.Synchronizer)) <> 0 then
  raise ESHMSSystemError.CreateFmt('TSharedMemory.Lock: Failed to lock (%d).',[errno_ptr^]);
{$ENDIF}
end;

//------------------------------------------------------------------------------

procedure TSharedMemory.Unlock;
begin
{$IFDEF Windows}
ReleaseMutex(fMappingSync);
{$ELSE}
pthread_mutex_unlock(Addr(fFooterPtr^.Synchronizer))
{$ENDIF}
end;


{===============================================================================
--------------------------------------------------------------------------------
                              TSharedMemoryStream                                                             
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TSharedMemoryStream - class implementation
===============================================================================}
{-------------------------------------------------------------------------------
    TSharedMemoryStream - protected methods
-------------------------------------------------------------------------------}

Function TSharedMemoryStream.GetName: String;
begin
Result := fSharedMemory.Name;
end;

{-------------------------------------------------------------------------------
    TSharedMemoryStream - public methods
-------------------------------------------------------------------------------}

constructor TSharedMemoryStream.Create(InitSize: TMemSize; const Name: String);
var
  SharedMemory: TSharedMemory;
begin
SharedMemory := TSharedMemory.Create(InitSize,Name);
inherited Create(SharedMemory.Memory,SharedMemory.Size);
fSharedMemory := SharedMemory;
end;

//------------------------------------------------------------------------------

destructor TSharedMemoryStream.Destroy;
begin
FreeAndNil(fSharedMemory);
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

//------------------------------------------------------------------------------

procedure TSharedMemoryStream.Lock;
begin
fSharedMemory.Lock;
end;

//------------------------------------------------------------------------------

procedure TSharedMemoryStream.Unlock;
begin
fSharedMemory.Unlock;
end;

end.

