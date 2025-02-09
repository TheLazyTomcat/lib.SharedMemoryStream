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

  Version 1.2.6 (2024-05-03)

  Last change 2024-09-09

  ©2018-2024 František Milt

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
    AuxClasses         - github.com/TheLazyTomcat/Lib.AuxClasses
  * AuxExceptions      - github.com/TheLazyTomcat/Lib.AuxExceptions
    AuxTypes           - github.com/TheLazyTomcat/Lib.AuxTypes
  * InterlockedOps     - github.com/TheLazyTomcat/Lib.InterlockedOps
  * SimpleFutex        - github.com/TheLazyTomcat/Lib.SimpleFutex
    StaticMemoryStream - github.com/TheLazyTomcat/Lib.StaticMemoryStream
    StrRect            - github.com/TheLazyTomcat/Lib.StrRect

  Library AuxExceptions is required only when rebasing local exception classes
  (see symbol SharedMemoryStream_UseAuxExceptions for details).

  Libraries SimpleFutex and InterlockedOps are required only when compiling for
  Linux operating system.

  Libraries AuxExceptions and InterlockedOps might also be required as an
  indirect dependencies.

  Indirect dependencies:
    SimpleCPUID - github.com/TheLazyTomcat/Lib.SimpleCPUID
    UInt64Utils - github.com/TheLazyTomcat/Lib.UInt64Utils
    WinFileInfo - github.com/TheLazyTomcat/Lib.WinFileInfo

===============================================================================}
unit SharedMemoryStream;
{
  SharedMemoryStream_UseAuxExceptions

  If you want library-specific exceptions to be based on more advanced classes
  provided by AuxExceptions library instead of basic Exception class, and don't
  want to or cannot change code in this unit, you can define global symbol
  SharedMemoryStream_UseAuxExceptions to achieve this.
}
{$IF Defined(SharedMemoryStream_UseAuxExceptions)}
  {$DEFINE UseAuxExceptions}
{$IFEND}

//------------------------------------------------------------------------------

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
  SysUtils, Classes, {$IFDEF Linux}BaseUnix,{$ENDIF}
  AuxTypes, AuxClasses, StaticMemoryStream{$IFDEF Linux}, SimpleFutex{$ENDIF}
  {$IFDEF UseAuxExceptions}, AuxExceptions{$ENDIF};

{===============================================================================
    Library-specific exceptions
===============================================================================}
type
  ESHMSException = class({$IFDEF UseAuxExceptions}EAEGeneralException{$ELSE}Exception{$ENDIF});

  ESHMSInvalidValue         = class(ESHMSException);
  ESHMSMutexCreationError   = class(ESHMSException);
  ESHMSMappingCreationError = class(ESHMSException);
  ESHMSMemoryMappingError   = class(ESHMSException);

  // following two exceptions can only be raised in linux, but are declared everywhere
  ESHMSMappingTruncateError = class(ESHMSException);
  ESHMSMappingIncompatible  = class(ESHMSException);

  ESHMSLockError   = class(ESHMSException);
  ESHMSUnlockError = class(ESHMSException);

{===============================================================================
--------------------------------------------------------------------------------
                               TSimpleSharedMemory
--------------------------------------------------------------------------------
===============================================================================}
type
  TCreationOption = (coRegisterInstance,coCrossArchitecture,coRobustInstance);
  TCreationOptions = set of TCreationOption;

const
  SHMS_CREATOPTS_DEFAULT = [coRegisterInstance{$IFNDEF Windows},coRobustInstance{$ENDIF}];

{===============================================================================
    TSimpleSharedMemory - class declaration
===============================================================================}
type
  TSimpleSharedMemory = class(TCustomObject)
  protected
    fCreationOptions: TCreationOptions;
    fName:            String;
    fMemory:          Pointer;
    fSize:            TMemSize;
  {$IFDEF Windows}
    fMappingObj:      THandle;
    class Function GetMappingSuffix: WideString; virtual;
  {$ELSE}
    fMemoryBase:      Pointer;    // also address of the header
    fFullSize:        TMemSize;
  {$ENDIF}
    procedure InitializeSectionLock; virtual;
    procedure FinalizeSectionLock; virtual;
    procedure Initialize(InitSize: TMemSize; const Name: String; CreationOptions: TCreationOptions); virtual;
    procedure Finalize; virtual;
    class Function RectifyName(const Name: String): String; virtual;
  public
    constructor Create(InitSize: TMemSize; const Name: String; CreationOptions: TCreationOptions = SHMS_CREATOPTS_DEFAULT);
    destructor Destroy; override;
    Function RegisteredInstance: Boolean; virtual;
    procedure RegisterInstance; virtual;
    procedure UnregisterInstance; virtual;
    property CreationOptions: TCreationOptions read fCreationOptions;
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
    class Function GetMappingSuffix: WideString; override;
  {$ENDIF}
    procedure InitializeSectionLock; override;
    procedure FinalizeSectionLock; override;
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
    class Function GetSharedMemoryInstance(InitSize: TMemSize; const Name: String; CreationOptions: TCreationOptions): TSimpleSharedMemory; virtual;
  public
    constructor Create(InitSize: TMemSize; const Name: String; CreationOptions: TCreationOptions = SHMS_CREATOPTS_DEFAULT);
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
    class Function GetSharedMemoryInstance(InitSize: TMemSize; const Name: String; CreationOptions: TCreationOptions): TSimpleSharedMemory; override;
  public
    procedure Lock; virtual;
    procedure Unlock; virtual;
    Function Read(var Buffer; Count: LongInt): LongInt; override;
    Function Write(const Buffer; Count: LongInt): LongInt; override;
  end;

implementation

uses
  {$IFDEF Windows}Windows,{$ELSE}UnixType, StrUtils,{$ENDIF} SyncObjs, Contnrs,
  {$IFNDEF Windows}InterlockedOps,{$ENDIF} StrRect;

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
  SHMS_NAME_SUFFIX_SECT = WideString('@shms_sect'); // section :P
  SHMS_NAME_SUFFIX_SYNC = WideString('@shms_sync');

{$IF not Declared(UNICODE_STRING_MAX_CHARS)}
  UNICODE_STRING_MAX_CHARS = 32767;
{$IFEND}

{$ELSE}//-----------------------------------------------------------------------

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
  PTHREAD_MUTEX_ROBUST    = 1;

Function pthread_mutexattr_init(attr: pthread_mutexattr_p): cint; cdecl; external;
Function pthread_mutexattr_destroy(attr: pthread_mutexattr_p): cint; cdecl; external;
Function pthread_mutexattr_setpshared(attr: pthread_mutexattr_p; pshared: cint): cint; cdecl; external;
Function pthread_mutexattr_settype(attr: pthread_mutexattr_p; _type: cint): cint; cdecl; external;
Function pthread_mutexattr_setrobust(attr: pthread_mutexattr_p; robustness: cint): cint; cdecl; external;

Function pthread_mutex_init(mutex: pthread_mutex_p; attr: pthread_mutexattr_p): cint; cdecl; external;
Function pthread_mutex_destroy(mutex: pthread_mutex_p): cint; cdecl; external;
Function pthread_mutex_lock(mutex: pthread_mutex_p): cint; cdecl; external;
Function pthread_mutex_unlock(mutex: pthread_mutex_p): cint; cdecl; external;
Function pthread_mutex_consistent(mutex: pthread_mutex_p): cint; cdecl; external;

Function shm_open(name: pchar; oflag: cint; mode: mode_t): cint; cdecl; external;
Function shm_unlink(name: pchar): cint; cdecl; external;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

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

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
type
  TSharedMemoryHeader = record
    HeaderLock:     TSimpleRobustMutexState;
    Flags:          UInt32;
    ReferenceCount: Int32;
    SectionLock:    record
      case Integer of
        0: (PthreadMutex: pthread_mutex_t);
        1: (SimpleMutex:  TSimpleRecursiveMutexState);
    end;
  end;
  PSharedMemoryHeader = ^TSharedMemoryHeader;

const
  SHMS_HEADFLAG_SECTLOCK  = 1;
  SHMS_HEADFLAG_CROSSARCH = 2;
  SHMS_HEADFLAG_ROBUST    = 4;
  SHMS_HEADFLAG_64BIT     = 8;

{$ENDIF}

{===============================================================================
    TSimpleSharedMemory - instance cleanup
===============================================================================}
{
  Following code is here to automatically free instances of shared memory
  objects that are still unfreed at the program termination.

  In Windows, these dangling instances pose no problem, because system
  automatically closes all handles when the process exits. But in Linux,
  we manage reference count internally, and any instance that is not freed
  explicitly would leave that count in inconsistent state.

  But note that this protects only when the process exits normally, not when it
  is killed or crashes.
}
var
  IC_InstancesSync:  TCriticalSection = nil;
  IC_Instances:      TObjectList = nil;
  IC_Finalizing:     Boolean = False;

//------------------------------------------------------------------------------

procedure InstanceCleanupInitialize;
begin
IC_InstancesSync := TCriticalSection.Create;
IC_Instances := TObjectList.Create(True);
end;

//------------------------------------------------------------------------------

procedure InstanceCleanupFinalize;
begin
IC_Finalizing := True;
FreeAndNil(IC_Instances); // all still registered instances are freed here
FreeAndNil(IC_InstancesSync);
end;

//==============================================================================

Function InstanceCleanupRegistered(Instance: TObject): Boolean;
begin
If not IC_Finalizing then
  begin
    IC_InstancesSync.Enter;
    try
      Result := IC_Instances.IndexOf(Instance) >= 0;
    finally
      IC_InstancesSync.Leave;
    end;
  end
else Result := False;
end;

//------------------------------------------------------------------------------

procedure InstanceCleanupRegister(Instance: TObject);
begin
If not IC_Finalizing then
  begin
    IC_InstancesSync.Enter;
    try
      // add the instance only when not already present
      If IC_Instances.IndexOf(Instance) < 0 then
        IC_Instances.Add(Instance);
    finally
      IC_InstancesSync.Leave;
    end;
  end;
end;

//------------------------------------------------------------------------------

procedure InstanceCleanupUnregister(Instance: TObject);
begin
If not IC_Finalizing then
  begin
    IC_InstancesSync.Enter;
    try
      // do not call Remove, as that would free the object
      IC_Instances.Extract(Instance);
    finally
      IC_InstancesSync.Leave;
    end;
  end;
end;


{===============================================================================
    TSimpleSharedMemory - class implementation
===============================================================================}
{-------------------------------------------------------------------------------
    TSimpleSharedMemory - protected methods
-------------------------------------------------------------------------------}
{$IFDEF Windows}
class Function TSimpleSharedMemory.GetMappingSuffix: WideString;
begin
Result := '';
end;

//------------------------------------------------------------------------------
{$ENDIF}

procedure TSimpleSharedMemory.InitializeSectionLock;
begin
// do nothing here, section lock is only created in non-simple descendants
end;

//------------------------------------------------------------------------------

procedure TSimpleSharedMemory.FinalizeSectionLock;
begin
// do nothing...
end;

//------------------------------------------------------------------------------

procedure TSimpleSharedMemory.Initialize(InitSize: TMemSize; const Name: String; CreationOptions: TCreationOptions);

{$IFNDEF Windows}

  procedure InitializeHeaderFlags(HeaderPtr: PSharedMemoryHeader);
  begin
    HeaderPtr^.Flags := 0;
    If Self.InheritsFrom(TSharedMemory{NOT simple}) then
      HeaderPtr^.Flags := HeaderPtr^.Flags or SHMS_HEADFLAG_SECTLOCK;
    If coCrossArchitecture in fCreationOptions then
      HeaderPtr^.Flags := HeaderPtr^.Flags or SHMS_HEADFLAG_CROSSARCH;
    If coRobustInstance in fCreationOptions then
      HeaderPtr^.Flags := HeaderPtr^.Flags or SHMS_HEADFLAG_ROBUST;
  {$IFDEF CPU64bit}
    HeaderPtr^.Flags := HeaderPtr^.Flags or SHMS_HEADFLAG_64BIT;
  {$ELSE}
    HeaderPtr^.Flags := HeaderPtr^.Flags and not SHMS_HEADFLAG_64BIT;
  {$ENDIF}
  end;

//--  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --

  procedure CheckHeaderFlags(HeaderPtr: PSharedMemoryHeader);
  begin
    If Self.InheritsFrom(TSharedMemory) <> (HeaderPtr^.Flags and SHMS_HEADFLAG_SECTLOCK <> 0) then
      raise ESHMSMappingIncompatible.Create('TSimpleSharedMemory.Initialize.CheckHeaderFlags: Section lock incompatibility.');
    If (coCrossArchitecture in fCreationOptions) <> (HeaderPtr^.Flags and SHMS_HEADFLAG_CROSSARCH <> 0) then
      raise ESHMSMappingIncompatible.Create('TSimpleSharedMemory.Initialize.CheckHeaderFlags: Cross-architecture incompatibility.');
    If (coRobustInstance in fCreationOptions) <> (HeaderPtr^.Flags and SHMS_HEADFLAG_ROBUST <> 0) then
      raise ESHMSMappingIncompatible.Create('TSimpleSharedMemory.Initialize.CheckHeaderFlags: Robustness incompatibility.');
    If not (coCrossArchitecture in fCreationOptions) then
      begin
      {$IFDEF CPU64bit}
        If HeaderPtr^.Flags and SHMS_HEADFLAG_64BIT = 0 then
      {$ELSE}
        If HeaderPtr^.Flags and SHMS_HEADFLAG_64BIT <> 0 then
      {$ENDIF}
          raise ESHMSMappingIncompatible.Create('TSimpleSharedMemory.Initialize.CheckHeaderFlags: Binary incompatibility.');
      end;
  end;

//--  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --   

  Function TryInitialize: Boolean;
  var
    MappingObj: cint;
    HeaderPtr:  PSharedMemoryHeader;
  begin
    Result := False;
    // add space for header, ensure alignment on 1024 bits (128 bytes) boundary
    fFullSize := (TMemSize(SizeOf(TSharedMemoryHeader) + 127) and not TMemSize(127)) + fSize;
    // create/open mapping
    MappingObj := shm_open(PChar(StrToSys(fName)),O_CREAT or O_RDWR,S_IRWXU);
    If MappingObj >= 0 then
      try
        If ftruncate(MappingObj,off_t(fFullSize)) < 0 then
          raise ESHMSMappingTruncateError.CreateFmt('TSimpleSharedMemory.Initialize.TryInitialize: Failed to truncate mapping (%d).',[errno_ptr^]);
        // ensure the header lock sees zeroed memory in case the mapping was just now created
        ReadWriteBarrier;
        // map file into memory
        fMemoryBase := mmap(nil,size_t(fFullSize),PROT_READ or PROT_WRITE,MAP_SHARED,MappingObj,0);
        If Assigned(fMemoryBase) and (fMemoryBase <> Pointer(-1){MAP_FAILED}) then
          begin
            HeaderPtr := fMemoryBase;
          {$IFDEF FPCDWM}{$PUSH}W4055{$ENDIF}
            fMemory := Pointer(PtrUInt(fMemoryBase) + PtrUInt(fFullSize - fSize));
          {$IFDEF FPCDWM}{$POP}{$ENDIF}
            SimpleRobustMutexLock(HeaderPtr^.HeaderLock);
            try
              If HeaderPtr^.ReferenceCount = 0 then
                begin
                {
                  This is the first time the mapping is accessed - set flags,
                  create section lock (if required) and set reference count to 1.
                }
                  InitializeHeaderFlags(HeaderPtr);
                  InitializeSectionLock;
                  HeaderPtr^.ReferenceCount := 1;
                  Result := True;
                end
              else If HeaderPtr^.ReferenceCount > 0 then
                begin
                {
                  The mapping and section lock are set up, check flags against
                  creation options and then increase reference count.

                  Note that the ref count must be incremented first - if flags
                  check fails with an exception, then destructor is executed
                  and the count is decremented there.
                }
                  Inc(HeaderPtr^.ReferenceCount);
                  CheckHeaderFlags(HeaderPtr);
                  Result := True;
                end
            {
              The mapping was unlinked and section lock destroyed somewhere
              between shm_open and SimpleRobustMutexLock - drop current mapping
              and start mapping again from scratch.
            }
              else munmap(fMemoryBase,size_t(fFullSize));
            finally
              SimpleRobustMutexUnlock(HeaderPtr^.HeaderLock);
            end;
          end
        else raise ESHMSMemoryMappingError.CreateFmt('TSimpleSharedMemory.Initialize.TryInitialize: Failed to map memory (%d).',[errno_ptr^]);
      finally
        close(MappingObj);
      end
    else raise ESHMSMappingCreationError.CreateFmt('TSimpleSharedMemory.Initialize.TryInitialize: Failed to create mapping (%d).',[errno_ptr^]);
  end;

{$ENDIF}

begin
fCreationOptions := CreationOptions;
{$IFNDEF Windows}
If coRobustInstance in fCreationOptions then
  Include(fCreationOptions,coRegisterInstance);
{$ENDIF}
If coRegisterInstance in fCreationOptions then
  RegisterInstance;
fName := RectifyName(Name);
If Length(fName) <= 0 then
  raise ESHMSInvalidValue.Create('TSimpleSharedMemory.Initialize: Empty name not allowed.');
fSize := InitSize;
{$IFDEF Windows}
InitializeSectionLock;
// create/open memory mapping
fMappingObj := CreateFileMappingW(INVALID_HANDLE_VALUE,nil,PAGE_READWRITE or SEC_COMMIT,
  DWORD(UInt64(fSize) shr 32),DWORD(fSize),PWideChar(StrToWide(fName) + GetMappingSuffix));
If fMappingObj = 0 then
  raise ESHMSMappingCreationError.CreateFmt('TSimpleSharedMemory.Initialize: Failed to create mapping (%d).',[GetLastError]);
// map memory
fMemory := MapViewOfFile(fMappingObj,FILE_MAP_ALL_ACCESS,0,0,fSize);
If not Assigned(fMemory) then
  raise ESHMSMemoryMappingError.CreateFmt('TSimpleSharedMemory.Initialize: Failed to map memory (%d).',[GetLastError]);
{$ELSE}
while not TryInitialize do
  sched_yield;
{$ENDIF}
end;

//------------------------------------------------------------------------------

procedure TSimpleSharedMemory.Finalize;
{$IFDEF Windows}
begin
UnmapViewOfFile(Memory);
CloseHandle(fMappingObj);
FinalizeSectionLock;
{$ELSE}
var
  HeaderPtr:  PSharedMemoryHeader;
begin
{
  If there was exception in the constructor, the header pointer might not be
  set by this point.
}
If Assigned(fMemoryBase) then
  begin
    HeaderPtr := fMemoryBase;
    SimpleRobustMutexLock(HeaderPtr^.HeaderLock);
    try
      If HeaderPtr^.ReferenceCount = 0 then
        begin
        {
          Zero should be possible only if the initialization failed when
          creating the section lock.
          Unlink the mapping but do not destroy section lock as it should not
          exist.
        }
          HeaderPtr^.ReferenceCount := -1;
          shm_unlink(PChar(StrToSys(fName)));
        end
      else If HeaderPtr^.ReferenceCount = 1 then
        begin
        {
          This is the last instance, destroy section lock and unlink the
          mapping.
          Set reference counter to -1 to indicate it is being destroyed.
        }
          HeaderPtr^.ReferenceCount := -1;
          // destroy section lock
          FinalizeSectionLock;
          // unlink mapping (ignore errors)
          shm_unlink(PChar(StrToSys(fName)));
        end
      else If HeaderPtr^.ReferenceCount > 1 then
        Dec(HeaderPtr^.ReferenceCount);
      {
        Negative value means the mapping is already being destroyed elsewhere,
        so do nothing.
      }
    finally
      SimpleRobustMutexUnlock(HeaderPtr^.HeaderLock);
    end;
  end;
// unmapping is done in any case...
If Assigned(fMemoryBase) and (fMemoryBase <> Pointer(-1)) then
  munmap(fMemoryBase,size_t(fFullSize));
{$ENDIF}
{
  Try to unregister this instance irrespective of creation options - the
  instance could have been registered by the user (by a call to method
  RegisterInstance) without including coRegisterInstance option.
}
UnregisterInstance;
end;

//------------------------------------------------------------------------------

class Function TSimpleSharedMemory.RectifyName(const Name: String): String;
var
  i:        Integer;
{$IFDEF Windows}
  Cnt:      Integer;
  TempWStr: WideString;
begin
{
  Windows

  Convert to lower case and limit the length while accounting for suffixes.
  There can be exactly one backslash (separating namespace prefix), replace
  other backslashes by underscores.

  Also note that all system calls here are done to unicode functions, so we
  must work with unicode-encoded string.
}
TempWStr := StrToWide(AnsiLowerCase(Name));
If (Length(TempWStr) + Length(GetMappingSuffix)) > UNICODE_STRING_MAX_CHARS then
  SetLength(TempWStr,UNICODE_STRING_MAX_CHARS - Length(GetMappingSuffix));
Cnt := 0;
For i := 1 to Length(TempWStr) do
  If TempWStr[i] = '\' then
    begin
      If Cnt > 0 then
        TempWStr[i] := '_';
      Inc(Cnt);
    end;
Result := WideToStr(TempWStr);
{$ELSE}
begin
{
  Linux

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
{$ENDIF}
end;

{-------------------------------------------------------------------------------
    TSimpleSharedMemory - public methods
-------------------------------------------------------------------------------}

constructor TSimpleSharedMemory.Create(InitSize: TMemSize; const Name: String; CreationOptions: TCreationOptions = SHMS_CREATOPTS_DEFAULT);
begin
inherited Create;
Initialize(InitSize,Name,CreationOptions);
end;

//------------------------------------------------------------------------------

destructor TSimpleSharedMemory.Destroy;
begin
Finalize;
inherited;
end;

//------------------------------------------------------------------------------

Function TSimpleSharedMemory.RegisteredInstance: Boolean;
begin
Result := InstanceCleanupRegistered(Self);
end;

//------------------------------------------------------------------------------

procedure TSimpleSharedMemory.RegisterInstance;
begin
InstanceCleanupRegister(Self);
end;

//------------------------------------------------------------------------------

procedure TSimpleSharedMemory.UnregisterInstance;
begin
InstanceCleanupUnregister(Self);
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
class Function TSharedMemory.GetMappingSuffix: WideString;
begin
// do not call inherited code
Result := SHMS_NAME_SUFFIX_SECT;
end;

//------------------------------------------------------------------------------
{$ENDIF}

procedure TSharedMemory.InitializeSectionLock;
{$IFDEF Windows}
begin
// create/open synchronization mutex
fMappingSync := CreateMutexW(nil,False,PWideChar(StrToWide(fName) + SHMS_NAME_SUFFIX_SYNC));
If fMappingSync = 0 then
  raise ESHMSMutexCreationError.CreateFmt('TSharedMemory.InitializeSectionLock: Failed to create mutex (%d).',[GetLastError]);
end;
{$ELSE}
var
  MutexAttr:  pthread_mutexattr_t;
begin
If not (coCrossArchitecture in fCreationOptions) then
  begin
    If ErrChk(pthread_mutexattr_init(@MutexAttr)) then
      try
        If not ErrChk(pthread_mutexattr_setpshared(@MutexAttr,PTHREAD_PROCESS_SHARED)) then
          raise ESHMSMutexCreationError.CreateFmt('TSharedMemory.InitializeSectionLock: Failed to set mutex attribute pshared (%d).',[ThrErrorCode]);
        If not ErrChk(pthread_mutexattr_settype(@MutexAttr,PTHREAD_MUTEX_RECURSIVE)) then
          raise ESHMSMutexCreationError.CreateFmt('TSharedMemory.InitializeSectionLock: Failed to set mutex attribute type (%d).',[ThrErrorCode]);
        If not ErrChk(pthread_mutexattr_setrobust(@MutexAttr,PTHREAD_MUTEX_ROBUST)) then
          raise ESHMSMutexCreationError.CreateFmt('TSharedMemory.InitializeSectionLock: Failed to set mutex attribute robust (%d).',[ThrErrorCode]);
        If not ErrChk(pthread_mutex_init(Addr(PSharedMemoryHeader(fMemoryBase)^.SectionLock.PthreadMutex),@MutexAttr)) then
          raise ESHMSMutexCreationError.CreateFmt('TSharedMemory.InitializeSectionLock: Failed to init mutex (%d).',[ThrErrorCode]);
      finally
        pthread_mutexattr_destroy(@MutexAttr);
      end
    else raise ESHMSMutexCreationError.CreateFmt('TSharedMemory.InitializeSectionLock: Failed to init mutex attributes (%d).',[ThrErrorCode]);
  end
else SimpleRecursiveMutexInit(PSharedMemoryHeader(fMemoryBase)^.SectionLock.SimpleMutex);
end;
{$ENDIF}

//------------------------------------------------------------------------------

procedure TSharedMemory.FinalizeSectionLock;
begin
{$IFDEF Windows}
CloseHandle(fMappingSync);
{$ELSE}
If not (coCrossArchitecture in fCreationOptions) then
  pthread_mutex_destroy(Addr(PSharedMemoryHeader(fMemoryBase)^.SectionLock.PthreadMutex)) // ignore errors
else
  SimpleRecursiveMutexInit(PSharedMemoryHeader(fMemoryBase)^.SectionLock.SimpleMutex);    // using init here is not an error
{$ENDIF}
end;

{-------------------------------------------------------------------------------
    TSharedMemory - public methods
-------------------------------------------------------------------------------}

procedure TSharedMemory.Lock;
{$IFDEF Windows}
begin
If not(WaitForSingleObject(fMappingSync,INFINITE) in [WAIT_ABANDONED,WAIT_OBJECT_0]) then
  raise ESHMSLockError.Create('TSharedMemory.Lock: Failed to lock.');
end;
{$ELSE}
var
  ReturnValue:  cint;
begin
If not (coCrossArchitecture in fCreationOptions) then
  begin
    ReturnValue := pthread_mutex_lock(Addr(PSharedMemoryHeader(fMemoryBase)^.SectionLock.PthreadMutex));
    If ReturnValue = ESysEOWNERDEAD then
      begin
      {
        Owner of the mutex died, it is now owned by the calling thread, but
        must be made consistent to use it again.
      }
        If not ErrChk(pthread_mutex_consistent(Addr(PSharedMemoryHeader(fMemoryBase)^.SectionLock.PthreadMutex))) then
          raise ESHMSLockError.CreateFmt('TSharedMemory.Lock: Failed to make mutex consistent (%d).',[ThrErrorCode]);
      end
    else If not ErrChk(ReturnValue) then
      raise ESHMSLockError.CreateFmt('TSharedMemory.Lock: Failed to lock (%d).',[ThrErrorCode]);
  end
else SimpleRecursiveMutexLock(PSharedMemoryHeader(fMemoryBase)^.SectionLock.SimpleMutex);
end;
{$ENDIF}

//------------------------------------------------------------------------------

procedure TSharedMemory.Unlock;
begin
{$IFDEF Windows}
If not ReleaseMutex(fMappingSync) then
  raise ESHMSUnlockError.CreateFmt('TSharedMemory.Unlock: Failed to unlock (%d).',[GetLastError]);
{$ELSE}
If not (coCrossArchitecture in fCreationOptions) then
  begin
    If not ErrChk(pthread_mutex_unlock(Addr(PSharedMemoryHeader(fMemoryBase)^.SectionLock.PthreadMutex))) then
      raise ESHMSUnlockError.CreateFmt('TSharedMemory.Unlock: Failed to unlock (%d).',[ThrErrorCode]);
  end
else SimpleRecursiveMutexUnlock(PSharedMemoryHeader(fMemoryBase)^.SectionLock.SimpleMutex);
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

class Function TSimpleSharedMemoryStream.GetSharedMemoryInstance(InitSize: TMemSize; const Name: String; CreationOptions: TCreationOptions): TSimpleSharedMemory;
begin
Result := TSimpleSharedMemory.Create(InitSize,Name,CreationOptions);
end;

{-------------------------------------------------------------------------------
    TSharedMemoryStream - public methods
-------------------------------------------------------------------------------}

constructor TSimpleSharedMemoryStream.Create(InitSize: TMemSize; const Name: String; CreationOptions: TCreationOptions = SHMS_CREATOPTS_DEFAULT);
var
  SharedMemory: TSimpleSharedMemory;
begin
SharedMemory := GetSharedMemoryInstance(InitSize,Name,CreationOptions);
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

class Function TSharedMemoryStream.GetSharedMemoryInstance(InitSize: TMemSize; const Name: String; CreationOptions: TCreationOptions): TSimpleSharedMemory;
begin
// do not call inherited code
Result := TSharedMemory.Create(InitSize,Name,CreationOptions);
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


{===============================================================================
--------------------------------------------------------------------------------
                                 Unit init/final
--------------------------------------------------------------------------------
===============================================================================}
initialization
  InstanceCleanupInitialize;

finalization
  InstanceCleanupFinalize;

end.
