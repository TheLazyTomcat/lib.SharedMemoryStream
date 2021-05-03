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

  Version 1.1.2 (2021-05-03)

  Last change 2021-05-03

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

  ESHMSSystemError   = class(ESHMSException);
  ESHMSRefCountError = class(ESHMSException); // used only in Linux

{===============================================================================
--------------------------------------------------------------------------------
                                 TSharedMemory
--------------------------------------------------------------------------------
===============================================================================}
{$IFDEF Linux}
type
  TSharedMemoryHeader = record
    Synchronizer: pthread_mutex_t;
    RefCount:     Int32;
  end;
  PSharedMemoryHeader = ^tSharedMemoryHeader;
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
    fMemoryBase:  Pointer;
    fFullSize:    TMemSize;
    fHeaderPtr:   PSharedMemoryHeader;
    Function LockRefCount: Int32; virtual;
    procedure InitializeMutex; virtual;
    Function TryInitialize: Boolean; virtual;
  {$ENDIF}
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
                                 TSharedMemory
--------------------------------------------------------------------------------
===============================================================================}
{$IFDEF Windows}

const
  SHMS_NAME_SUFFIX_MAP  = '_shms_map';
  SHMS_NAME_SUFFIX_SYNC = '_shms_sync';

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

{$ENDIF}

{===============================================================================
    TSharedMemory - class implementation
===============================================================================}
{-------------------------------------------------------------------------------
    TSharedMemory - protected methods
-------------------------------------------------------------------------------}

{$IFDEF Windows}

procedure TSharedMemory.Initialize;
begin
// create/open synchronization mutex
fMappingSync := CreateMutexW(nil,False,PWideChar(StrToWide(fName + SHMS_NAME_SUFFIX_SYNC)));
If fMappingSync = 0 then
  raise ESHMSSystemError.CreateFmt('TSharedMemory.InitializeLock: Failed to create mutex (0x%.8x).',[GetLastError]);
// create/open memory mapping
fMappingObj := CreateFileMappingW(INVALID_HANDLE_VALUE,nil,PAGE_READWRITE or SEC_COMMIT,DWORD(UInt64(fSize) shr 32),
                                  DWORD(fSize),PWideChar(StrToWide(fName + SHMS_NAME_SUFFIX_MAP)));
If fMappingObj = 0 then
  raise ESHMSSystemError.CreateFmt('TSharedMemory.Initialize: Failed to create mapping (0x%.8x).',[GetLastError]);
// map memory
fMemory := MapViewOfFile(fMappingObj,FILE_MAP_ALL_ACCESS,0,0,fSize);
If not Assigned(fMemory) then
  raise ESHMSSystemError.CreateFmt('TSharedMemory.Initialize: Failed to map memory (0x%.8x).',[GetLastError]);
end;

//------------------------------------------------------------------------------

procedure TSharedMemory.Finalize;
begin
UnmapViewOfFile(Memory);
CloseHandle(fMappingObj);
CloseHandle(fMappingSync);
end;

//------------------------------------------------------------------------------

class Function TSharedMemory.RectifyName(const Name: String): String;
var
  i,Cnt:  Integer;
begin
{
  There can be exactly one backslash (separating namespace prefix).
  Replace other backslashes by underscores and convert to lower case. Do not
  limit length.
}
Result := AnsiLowerCase(Name);
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

// constants for reference counter
const
  SHMS_REFCNT_DMAX = -2;
  SHMS_REFCNT_LOCK = -1;
  SHMS_REFCNT_INIT = 0;
  SHMS_REFCNT_RMAX = 2000000000;

//------------------------------------------------------------------------------

Function TSharedMemory.LockRefCount: Int32;
begin
repeat
  Result := InterlockedExchange(fHeaderPtr^.RefCount,SHMS_REFCNT_LOCK);
  If Result = SHMS_REFCNT_LOCK then
    sched_yield;  // ref counter was locked, wait a moment and try again
until Result <> SHMS_REFCNT_LOCK;
end;

//------------------------------------------------------------------------------

procedure TSharedMemory.InitializeMutex;
var
  MutexAttr:  pthread_mutexattr_t;
begin
If pthread_mutexattr_init(@MutexAttr) = 0 then
  try
    If pthread_mutexattr_setpshared(@MutexAttr,PTHREAD_PROCESS_SHARED) <> 0 then
      raise ESHMSSystemError.CreateFmt('TSharedMemory.InitializeLock: Failed to set mutex attribute pshared (%d).',[errno_ptr^]);
    If pthread_mutexattr_settype(@MutexAttr,PTHREAD_MUTEX_RECURSIVE) <> 0 then
      raise ESHMSSystemError.CreateFmt('TSharedMemory.InitializeLock: Failed to set mutex attribute type (%d).',[errno_ptr^]);
    If pthread_mutex_init(Addr(fHeaderPtr^.Synchronizer),@MutexAttr) <> 0 then
      raise ESHMSSystemError.CreateFmt('TSharedMemory.InitializeLock: Failed to init mutex (%d).',[errno_ptr^]);
  finally
    pthread_mutexattr_destroy(@MutexAttr);
  end
else raise ESHMSSystemError.CreateFmt('TSharedMemory.InitializeLock: Failed to init mutex attributes (%d).',[errno_ptr^]);
end;

//------------------------------------------------------------------------------

Function TSharedMemory.TryInitialize: Boolean;
var
  MappingObj:   cint;
  OldRefCount:  Int32;
begin
Result := False;
// add aligned space for footer
fFullSize := ((fSize + 127) and not TMemSize(127)) + SizeOf(TSharedMemoryHeader);
// create/open mapping
MappingObj := shm_open(PChar(StrToSys(fName)),O_CREAT or O_RDWR,S_IRWXU);
If MappingObj >= 0 then
  try
    If ftruncate(MappingObj,off_t(fFullSize)) < 0 then
      raise ESHMSSystemError.CreateFmt('TSharedMemory.TryInitialize: Failed to truncate mapping (%d).',[errno_ptr^]);
    // map file into memory
    fMemoryBase := mmap(nil,size_t(fFullSize),PROT_READ or PROT_WRITE,MAP_SHARED,MappingObj,0);
    If Assigned(fMemoryBase) and (fMemoryBase <> Pointer(-1)) then
      begin
        fHeaderPtr := fMemoryBase;
      {$IFDEF FPCDWM}{$PUSH}W4055{$ENDIF}
        fMemory := Pointer(PtrUInt(fMemoryBase) + PtrUInt((fSize + 127) and not TMemSize(127)));
      {$IFDEF FPCDWM}{$POP}{$ENDIF}
        OldRefCount := LockRefCount;
        try
          If OldRefCount <= SHMS_REFCNT_DMAX{-2} then
            begin
            {
              The mapping was unlinked and mutex destroyed somewhere between
              shm_open and LockRefCount - drop current mapping and start
              mapping again from scratch.
            }
              munmap(fMemoryBase,size_t(fFullSize));
              InterlockedExchange(fHeaderPtr^.RefCount,OldRefCount);
            end
          else If OldRefCount = SHMS_REFCNT_INIT{0} then
            begin
            {
              This is the first time the mapping is accessed - create mutex and
              set reference count to 1.
            }
              InitializeMutex;
              InterlockedExchange(fHeaderPtr^.RefCount,Succ(SHMS_REFCNT_INIT){1});
              Result := True;
            end
          else If OldRefCount < SHMS_REFCNT_RMAX then
            begin
            {
              The mapping and mutex is set up, only increase reference count.
            }
              InterlockedExchange(fHeaderPtr^.RefCount,Succ(OldRefCount));
              Result := True;
            end
          else raise ESHMSRefCountError.CreateFmt('TSharedMemory.TryInitialize: Invalid reference count (%d).',[OldRefCount]);
        except
          InterlockedExchange(fHeaderPtr^.RefCount,OldRefCount);
          raise;
        end;
      end
    else raise ESHMSSystemError.CreateFmt('TSharedMemory.TryInitialize: Failed to map memory (%d).',[errno_ptr^]);
  finally
    close(MappingObj);
  end
else raise ESHMSSystemError.CreateFmt('TSharedMemory.TryInitialize: Failed to create mapping (%d).',[errno_ptr^]);
end;

//------------------------------------------------------------------------------

procedure TSharedMemory.Initialize;
begin
while not TryInitialize do
  sched_yield;
end;

//------------------------------------------------------------------------------

procedure TSharedMemory.Finalize;
var
  OldRefCount:  Int32;
begin
If Assigned(fHeaderPtr) then
  begin
    OldRefCount := LockRefCount;
    try
      If (OldRefCount <= SHMS_REFCNT_RMAX) and (OldRefCount <> 0) then
        begin
        {
          SHMS_REFCNT_LOCK (-1) is not possible here, other negative numbers
          mean everything is already cleared, so do nothing in that case.
        }
          If OldRefCount = Succ(SHMS_REFCNT_INIT){1} then
            begin
              // destroy mutex (ignore errors)
              pthread_mutex_destroy(Addr(fHeaderPtr^.Synchronizer));
              // unlink mapping (ignore errors)
              shm_unlink(PChar(StrToSys(fName)));
              InterlockedExchange(fHeaderPtr^.RefCount,Low(Int32)); // destroyed
            end
          else If OldRefCount > Succ(SHMS_REFCNT_INIT) then
            InterlockedExchange(fHeaderPtr^.RefCount,Pred(OldRefCount));
        end
      else raise ESHMSRefCountError.CreateFmt('TSharedMemory.Finalize: Invalid reference count (%d).',[OldRefCount]);
    except
      InterlockedExchange(fHeaderPtr^.RefCount,OldRefCount);
      raise;
    end;
  end;
If Assigned(fMemoryBase) and (fMemoryBase <> Pointer(-1)) then
  munmap(fMemoryBase,size_t(fFullSize));
end;

//------------------------------------------------------------------------------

class Function TSharedMemory.RectifyName(const Name: String): String;
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
end;

{$ENDIF}

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
If pthread_mutex_lock(Addr(fHeaderPtr^.Synchronizer)) <> 0 then
  raise ESHMSSystemError.CreateFmt('TSharedMemory.Lock: Failed to lock (%d).',[errno_ptr^]);
{$ENDIF}
end;

//------------------------------------------------------------------------------

procedure TSharedMemory.Unlock;
begin
{$IFDEF Windows}
ReleaseMutex(fMappingSync);
{$ELSE}
If pthread_mutex_unlock(Addr(fHeaderPtr^.Synchronizer)) <> 0 then
  raise ESHMSSystemError.CreateFmt('TSharedMemory.Lock: Failed to unlock (%d).',[errno_ptr^]);
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

