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

  Version 1.3.1 (2025-03-05)

  Last change 2025-03-05

  ©2018-2025 František Milt

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

  // following four exceptions can be raised only in Linux
  ESHMSMappingTruncateError = class(ESHMSException);
  ESHMSMappingIncompatible  = class(ESHMSException);
  ESHMSKeyGenerationError   = class(ESHMSException);
  ESHMSSemaphoreError       = class(ESHMSException);

  ESHMSLockError        = class(ESHMSException);
  ESHMSUnlockError      = class(ESHMSException);
  ESHMSConsistencyError = class(ESHMSException);

{===============================================================================
--------------------------------------------------------------------------------
                               TSimpleSharedMemory
--------------------------------------------------------------------------------
===============================================================================}
type
  TCreationOption = (optRegisterInstance,optCrossArchitecture,optRobustInstance);
  TCreationOptions = set of TCreationOption;

const
  SHMS_CREATOPTS_DEFAULT = [optRegisterInstance{$IFNDEF Windows},optRobustInstance{$ENDIF}];

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
    fRobustCounter:   cint;       // SysV semaphore set ID
    // all RobustCounter* methods must be executed when header is locked
    Function RobustCounterAttach: Int32; virtual;
    Function RobustCounterDetach: Int32; virtual;
  {$ENDIF}
    procedure SectionLockInitialize; virtual;
    procedure SectionLockFinalize; virtual;
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
    procedure SectionLockInitialize; override;
    procedure SectionLockFinalize; override;
  public
  {
    Lock

    If Lock returns true, it means the underlying mutex was succesfully
    acquired with no problems.
    But when false is returned, it means the mutex is acquired but was
    abandoned - meaning its previous owner died without releasing it.
    This can mean the protected data might be in an inconsistent state.
    You should check the data consistency and if correction is not possible,
    fail in some sensible way.
  }
    Function Lock: Boolean; virtual;
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
    procedure Initialize; virtual;
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
    fFailOnAbandonedLock: Boolean;
    class Function GetSharedMemoryInstance(InitSize: TMemSize; const Name: String; CreationOptions: TCreationOptions): TSimpleSharedMemory; override;
    procedure Initialize; override;
  public
  {
    Lock

    See TSharedMemory.Lock method.
  }
    Function Lock: Boolean; virtual;
    procedure Unlock; virtual;
    Function Read(var Buffer; Count: LongInt): LongInt; override;
    Function Write(const Buffer; Count: LongInt): LongInt; override;
  {
    ReadNoLock
    WriteNoLock

    These two functions are non-locking variants of Read and Write (which
    are both serialized). They are here for situations where locking of each
    operation is not needed or desired.
  }
    Function ReadNoLock(var Buffer; Count: LongInt): LongInt; virtual;
    Function WriteNoLock(const Buffer; Count: LongInt): LongInt; virtual;
  {
    FailOnAbandonedLock

    If this property is set to True, then methods Read and Write will fail with
    an ESHMSConsistencyError exception when lock protecting the data indicates
    that it was abandoned (its previous owner died without unlocking it).
    Otherwise abandonment is ignored.
  }
    property FailOnAbandonedLock: Boolean read fFailOnAbandonedLock write fFailOnAbandonedLock;
  end;

implementation

uses
  {$IFDEF Windows}Windows,{$ELSE}UnixType, StrUtils,{$ENDIF} SyncObjs, Contnrs,
  {$IFNDEF FPC}Types{for inline expansion in newer Delphi}, {$ENDIF}
  {$IFNDEF Windows}InterlockedOps,{$ENDIF} StrRect;

{$IFDEF Linux}
  {$LINKLIB C}
  {$LINKLIB RT}
  {$LINKLIB PTHREAD}
{$ENDIF}

{$IFDEF FPC_DisableWarns}
  {$DEFINE FPCDWM}
  {$DEFINE W4055:={$WARN 4055 OFF}} // Conversion between ordinals and pointers is not portable
{$ENDIF}

{===============================================================================
    Common types, constants, externals, ...
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
type
  key_t = cint;

  sembuf_t = record
    sem_num:  cushort;
    sem_op:   cshort;
    sem_flg:  cshort;
  end;
  sembuf_p = ^sembuf_t;

{
  Fields buf and __buf are pointers to specific structures - but since we do
  not use them here, they are not declared and the fields are just untyped
  pointers.
}
  semun_t = record
    case Integer of
      0:  (val:   cint);
      1:  (buf:   pointer);
      2:  (arr:   pcushort);  // pointer to array of cushort
      3:  (__buf: pointer);
  end;

const
  IPC_CREAT  = $200;
  IPC_EXCL   = $400;
  IPC_NOWAIT = $800;

  IPC_RMID = 0;

  SEM_UNDO = $1000;

  GETVAL = 12;
  SETVAL = 16;

Function ftok(pathname: pchar; proj_id: cint): key_t; cdecl; external;

Function semget(key: key_t; nsems: cint; semflg: cint): cint; cdecl; external;
Function semctl(semid: cint; semnum: cint; cmd: cint): cint; varargs; cdecl; external;
Function semop(semid: cint; sops: sembuf_p; nsops: size_t): cint; cdecl; external;

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

//------------------------------------------------------------------------------
type
  TSharedMemoryHeader = record
    HeaderLock:     TSimpleRobustMutexState;
    Version:        UInt32;
    Flags:          UInt32;
    ReferenceCount: Int32;
    Reserved:       Int32;
    SectionLock:    record
      case Integer of
        0: (PthreadMutex: pthread_mutex_t);
        1: (SimpleMutex:  TSimpleRecursiveMutexState);
    end;
  end;
  PSharedMemoryHeader = ^TSharedMemoryHeader;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
const
  SHMS_HEADFLAG_SECTLOCK  = 1;
  SHMS_HEADFLAG_CROSSARCH = 2;
  SHMS_HEADFLAG_ROBUST    = 4;
  SHMS_HEADFLAG_64BIT     = 8;

  SHMS_INTERNAL_VERSION = 1;

{$ENDIF}

{===============================================================================
--------------------------------------------------------------------------------
                                Instance cleanup
--------------------------------------------------------------------------------
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
--------------------------------------------------------------------------------
                               TSimpleSharedMemory
--------------------------------------------------------------------------------
===============================================================================}
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
{$ELSE}

Function TSimpleSharedMemory.RobustCounterAttach: Int32;
var
  Key:      key_t;
  ErrCode:  cint;
  SemUn:    semun_t;
  SemBuf:   sembuf_t;

  Function DoRollback(RemoveSemSet: Boolean): cint;
  begin
    Result := errno_ptr^;
    If RemoveSemSet then
      semctl(fRobustCounter,0,IPC_RMID);  // ignore errors
    fRobustCounter := -1;
  end;

begin
{
  Note that this entire method, while containing multiple different actions,
  is executed atomically - that is in its entirety or not at all. In here this
  means any exception after the semaphore set is created/opened leads to a
  rollback that reverts previous actions.
}
Result := 0;
fRobustCounter := -1;
Key := ftok(PChar(StrToSys('/dev/shm' + fName)),1{0 not allowed});
If Key <> -1 then
  begin
    // try to create semaphore set in exclusive mode
    fRobustCounter := semget(Key,1,IPC_CREAT or IPC_EXCL or S_IRWXU);
    If fRobustCounter = -1 then
      begin
      {
        Something failed, if it is because the semaphore set already existed
        then try to open it.
      }
        ErrCode := errno_ptr^;
        If ErrCode = ESysEEXIST then
          begin
            fRobustCounter := semget(Key,1,S_IRWXU);
            If fRobustCounter <> -1 then
              begin
                // we have opened the set, get value
                Result := Int32(semctl(fRobustCounter,0,GETVAL));
                If Result = -1 then
                  begin
                    ErrCode := DoRollback(False);  // do not remove the set, we have only opened it
                    raise ESHMSSemaphoreError.CreateFmt('TSimpleSharedMemory.RobustCounterAttach: Failed to obtain semaphore value (%d).',[ErrCode]);
                  end;
              end
            else raise ESHMSSemaphoreError.CreateFmt('TSimpleSharedMemory.RobustCounterAttach: Failed to open semaphore (%d).',[errno_ptr^]);
          end
        else raise ESHMSSemaphoreError.CreateFmt('TSimpleSharedMemory.RobustCounterAttach: Failed to create semaphore (%d).',[ErrCode]);
      end
    else
      begin
        // we have created the semaphore, initialize it to zero
        SemUn.val := 0; // initial value for the semaphore
        If semctl(fRobustCounter,0,SETVAL,SemUn) = -1 then
          begin
            ErrCode := DoRollback(True);
            raise ESHMSSemaphoreError.CreateFmt('TSimpleSharedMemory.RobustCounterAttach: Failed to initialize semaphore (%d).',[ErrCode]);
          end;
      end;
  end
else raise ESHMSKeyGenerationError.CreateFmt('TSimpleSharedMemory.RobustCounterAttach: Cannot generate SysV IPC key (%d).',[errno_ptr^]);
{
  Now we have the semaphore set open and result is set to its current value,
  increment it.
}
SemBuf.sem_num := 0;
SemBuf.sem_op := +1;  // increment value by one
SemBuf.sem_flg := SEM_UNDO;
If semop(fRobustCounter,@SemBuf,1) = -1 then
  begin
    // if result is zero it means we have created the set and therefore can remove it
    ErrCode := DoRollback(Result = 0);
    raise ESHMSSemaphoreError.CreateFmt('TSimpleSharedMemory.RobustCounterAttach: Failed to increment semaphore (%d).',[ErrCode]);
  end;
end;

//------------------------------------------------------------------------------

Function TSimpleSharedMemory.RobustCounterDetach: Int32;
var
  SemBuf: sembuf_t;
begin
{
  There are no exceptions raised in here as this method is called from
  destructor - failure is indicated by returning a negative value, which
  tells destructor to do nothing.
}
Result := -1;
If fRobustCounter <> -1 then
  begin
    // first get actual semaphore value
    Result := Int32(semctl(fRobustCounter,0,GETVAL));
    If Result <> -1 then
      begin
        // we have got the actual value, do decrement
        SemBuf.sem_num := 0;
        SemBuf.sem_op := -1;  // decrement value by one
        SemBuf.sem_flg := IPC_NOWAIT or SEM_UNDO;
        If semop(fRobustCounter,@SemBuf,1) <> -1 then
          begin
            If Result <= 1 then // ie. the semaphore is now at zero
              semctl(fRobustCounter,0,IPC_RMID);  // ignore errors here
          end;
      end;
  end;
end;

//------------------------------------------------------------------------------
{$ENDIF}

procedure TSimpleSharedMemory.SectionLockInitialize;
begin
// do nothing here, section lock is only created in non-simple descendants
end;

//------------------------------------------------------------------------------

procedure TSimpleSharedMemory.SectionLockFinalize;
begin
// do nothing...
end;

//------------------------------------------------------------------------------

procedure TSimpleSharedMemory.Initialize(InitSize: TMemSize; const Name: String; CreationOptions: TCreationOptions);

{$IFNDEF Windows}

  procedure HeaderFlagsAndVersionInit(out Header: TSharedMemoryHeader);
  begin
    Header.Flags := 0;
    If Self.InheritsFrom(TSharedMemory{NOT simple}) then
      Header.Flags := Header.Flags or SHMS_HEADFLAG_SECTLOCK;
    If optCrossArchitecture in fCreationOptions then
      Header.Flags := Header.Flags or SHMS_HEADFLAG_CROSSARCH;
    If optRobustInstance in fCreationOptions then
      Header.Flags := Header.Flags or SHMS_HEADFLAG_ROBUST;
  {$IFDEF CPU64bit}
    Header.Flags := Header.Flags or SHMS_HEADFLAG_64BIT;
  {$ELSE}
    Header.Flags := Header.Flags and not SHMS_HEADFLAG_64BIT;
  {$ENDIF}
    Header.Version := SHMS_INTERNAL_VERSION;
  end;

//--  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --

  procedure HeaderFlagsAndVersionCheck(var Header: TSharedMemoryHeader);
  const
    // to shorten error msgs
    _FCENAME = 'TSimpleSharedMemory.Initialize.HeaderFlagsAndVersionCheck';
  begin
    If Self.InheritsFrom(TSharedMemory) <> (Header.Flags and SHMS_HEADFLAG_SECTLOCK <> 0) then
      raise ESHMSMappingIncompatible.Create(_FCENAME + ': Section lock incompatibility.');
    If (optCrossArchitecture in fCreationOptions) <> (Header.Flags and SHMS_HEADFLAG_CROSSARCH <> 0) then
      raise ESHMSMappingIncompatible.Create(_FCENAME + ': Cross-architecture incompatibility.');
    If (optRobustInstance in fCreationOptions) <> (Header.Flags and SHMS_HEADFLAG_ROBUST <> 0) then
      raise ESHMSMappingIncompatible.Create(_FCENAME + ': Robustness incompatibility.');
    If not (optCrossArchitecture in fCreationOptions) then
      begin
      {$IFDEF CPU64bit}
        If Header.Flags and SHMS_HEADFLAG_64BIT = 0 then
      {$ELSE}
        If Header.Flags and SHMS_HEADFLAG_64BIT <> 0 then
      {$ENDIF}
          raise ESHMSMappingIncompatible.Create(_FCENAME + ': Binary incompatibility.');
      end;
    If Header.Version <> SHMS_INTERNAL_VERSION then
      raise ESHMSMappingIncompatible.CreateFmt(_FCENAME +
        ': Internal version incompatibility (required %u; got %u)',
        [UInt32(SHMS_INTERNAL_VERSION),Header.Version]);
  end;

//--  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --

  Function HeaderProcess(var Header: TSharedMemoryHeader): Boolean;
  const
    _FCENAME = 'TSimpleSharedMemory.Initialize.HeaderProcess';
  begin
    Result := False;
    If SimpleRobustMutexLock(Header.HeaderLock) = lrSignaled then
      try
        If optRobustInstance in fCreationOptions then
          Header.ReferenceCount := RobustCounterAttach;
        If Header.ReferenceCount = 0 then
          begin
          {
            This seems to be the first time the mapping is accessed - set flags,
            create section lock (if required) and set reference count to 1.
          }
            SectionLockFinalize;        // in case we reopened abandonned mapping
            HeaderFlagsAndVersionInit(Header);
            SectionLockInitialize;
            Header.ReferenceCount := 1;
            FillChar(fMemory^,fSize,0); // same reason as for SectionLockFinalize
            Result := True;
          end
        else If Header.ReferenceCount > 0 then
          begin
          {
            The mapping and section lock are set up, check flags against
            creation options and increase reference count.

            Note that the ref count must be always incremented  - if flags
            check fails with an exception, or the reference count is too high,
            then destructor is executed and the count is decremented there.
          }
            try
              // protect against overflow
              If Header.ReferenceCount >= (High(Int32) shr 1{over one billion}) then
                raise ESHMSInvalidValue.CreateFmt(_FCENAME + ': Reference count too high (%d).',[Header.ReferenceCount]);
              HeaderFlagsAndVersionCheck(Header);
              Result := True;
            finally
              Inc(Header.ReferenceCount);
            end;
          end
      {
        Reference count is below 0 - the mapping file was unlinked and section
        lock destroyed somewhere between shm_open and SimpleRobustMutexLock -
        drop current mapping and start mapping again from scratch.
      }
        else munmap(fMemoryBase,size_t(fFullSize));
      finally
        SimpleRobustMutexUnlock(Header.HeaderLock);
      end
    else raise ESHMSConsistencyError.Create(_FCENAME + ': Lock was abandoned, internal data might be damaged.');
  end;

//--  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --

  Function TryInitialize: Boolean;
  const
    // to shorten error msgs
    _FCENAME = 'TSimpleSharedMemory.Initialize.TryInitialize';
  var
    MappingObj: cint;
  begin
    Result := False;
    // add space for header (use granularity to keep some of the potential alignment)
    fFullSize := (TMemSize(SizeOf(TSharedMemoryHeader) + 127) and not TMemSize(127)) + fSize;
    // create/open mapping
    MappingObj := shm_open(PChar(StrToSys(fName)),O_CREAT or O_RDWR,S_IRWXU);
    If MappingObj >= 0 then
      try
        If ftruncate(MappingObj,off_t(fFullSize)) < 0 then
          raise ESHMSMappingTruncateError.CreateFmt(_FCENAME + ': Failed to truncate mapping (%d).',[errno_ptr^]);
        // ensure the header lock sees zeroed memory in case the mapping was just now created
        ReadWriteBarrier;
        // map file into memory
        fMemoryBase := mmap(nil,size_t(fFullSize),PROT_READ or PROT_WRITE,MAP_SHARED,MappingObj,0);
        If Assigned(fMemoryBase) and (fMemoryBase <> Pointer(-1){MAP_FAILED}) then
          begin
            fRobustCounter := -1; // must be set before fMemory is assigned
          {$IFDEF FPCDWM}{$PUSH}W4055{$ENDIF}
            fMemory := Pointer(PtrUInt(fMemoryBase) + PtrUInt(fFullSize - fSize));
          {$IFDEF FPCDWM}{$POP}{$ENDIF}
            Result := HeaderProcess(PSharedMemoryHeader(fMemoryBase)^);
          end
        else raise ESHMSMemoryMappingError.CreateFmt(_FCENAME + ': Failed to map memory (%d).',[errno_ptr^]);
      finally
        close(MappingObj);
      end
    else raise ESHMSMappingCreationError.CreateFmt(_FCENAME + ': Failed to create mapping (%d).',[errno_ptr^]);
  end;

{$ENDIF}

begin
fCreationOptions := CreationOptions;
{$IFNDEF Windows}
If optRobustInstance in fCreationOptions then
  Include(fCreationOptions,optRegisterInstance);
{$ENDIF}
If optRegisterInstance in fCreationOptions then
  RegisterInstance;
fName := RectifyName(Name);
If Length(fName) <= 0 then
  raise ESHMSInvalidValue.Create('TSimpleSharedMemory.Initialize: Empty name not allowed.');
fSize := InitSize;
{$IFDEF Windows}
SectionLockInitialize;
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
SectionLockFinalize;
{$ELSE}

  procedure HeaderProcess(var Header: TSharedMemoryHeader);
  const
    _FCENAME = 'TSimpleSharedMemory.Finalize.HeaderProcess';
  begin
    If SimpleRobustMutexLock(Header.HeaderLock) = lrSignaled then
      try
        If optRobustInstance in fCreationOptions then
          begin
          {
            If robust counter was not initialized, it means no code working
            with header was run in the constructor - therefore there is no
            point in touching anything here.
          }
            If fRobustCounter <> -1 then
              Header.ReferenceCount := RobustCounterDetach
            else
              Exit; // do nothing
          end;
        If Header.ReferenceCount = 0 then
          begin
          {
            Zero should be possible only if the initialization failed when
            creating the section lock.
            Unlink the mapping but do not destroy section lock as it should not
            exist.
          }
            Header.ReferenceCount := -1;
            shm_unlink(PChar(StrToSys(fName)));
          end
        else If Header.ReferenceCount = 1 then
          begin
          {
            This is the last instance, destroy section lock and unlink the
            mapping.
            Set reference counter to -1 to indicate it is being destroyed.
          }
            Header.ReferenceCount := -1;
            // destroy section lock
            SectionLockFinalize;
            // unlink mapping (ignore errors)
            shm_unlink(PChar(StrToSys(fName)));
          end
        else If Header.ReferenceCount > 1 then
          Dec(Header.ReferenceCount);
        {
          Negative value means the mapping is already being destroyed elsewhere
          (or robust counter detachment failed), so do nothing.
        }
      finally
        SimpleRobustMutexUnlock(Header.HeaderLock);
      end
    else raise ESHMSConsistencyError.Create(_FCENAME + ': Lock was abandoned, internal data might be damaged.');;
  end;

begin
{
  Constructor exception rollback

  In case an exception is raised in constructor, pascal automatically runs
  object's destructor, and since the code executed in TSimpleSharedMemory
  constructor is rather complex, we must take care what to execute here to
  do proper rollback.
  Note that Windows is somewhat fool-proof in this regard, but since Linux is
  DIY territory, it will go complex fast...

  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    If an exception occurs before calling mmap, then both fields fMemory and
    fMemoryBase are left unassigned (nil) and no rollback or finalizing code
    is executed here - only the instance cleanup is performed (object is
    removed from the instance list).
    Note that, if we have created the file backing this mapping (shm_open,
    ftruncate), the file is NOT unlinked - simply because we cannot know
    whether we are the sole user of it by this point.
    This might be seen as a leak, but there is just no way to know what happens
    with the file between its creation and execution of cleanup code, so it is
    safer to make a small leak than to potentially crash other process or
    damage its data.

  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    If mmap fails, then again nothing is done as fMemoryBase will be set to
    Pointer(-1).
    This creates no leak, because if mapping fails, then no resources were
    allocated (no pages mapped) and there is nothing to unmap/free.

    If exception occurs anywhere after the fMemoryBase is assigned a valid
    value, then the memory is always unmapped (munmap).

  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    Right after mapping, the field fMemory is assigned its value - there is
    very low probability that code executed between mapping and this point
    could produce an exception, but if it does, then again only the unmapping
    is performed.

  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    Next steps are performed on the header, refer to descriptions in nested
    function HeaderProcess for more details.
}
If Assigned(fMemory) then
  HeaderProcess(PSharedMemoryHeader(fMemoryBase)^);
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

procedure TSharedMemory.SectionLockInitialize;
{$IFDEF Windows}
begin
// create/open synchronization mutex
fMappingSync := CreateMutexW(nil,False,PWideChar(StrToWide(fName) + SHMS_NAME_SUFFIX_SYNC));
If fMappingSync = 0 then
  raise ESHMSMutexCreationError.CreateFmt('TSharedMemory.SectionLockInitialize: Failed to create mutex (%d).',[GetLastError]);
end;
{$ELSE}
var
  MutexAttr:  pthread_mutexattr_t;
begin
If not (optCrossArchitecture in fCreationOptions) then
  begin
    If ErrChk(pthread_mutexattr_init(@MutexAttr)) then
      try
        If not ErrChk(pthread_mutexattr_setpshared(@MutexAttr,PTHREAD_PROCESS_SHARED)) then
          raise ESHMSMutexCreationError.CreateFmt('TSharedMemory.SectionLockInitialize: Failed to set mutex attribute pshared (%d).',[ThrErrorCode]);
        If not ErrChk(pthread_mutexattr_settype(@MutexAttr,PTHREAD_MUTEX_RECURSIVE)) then
          raise ESHMSMutexCreationError.CreateFmt('TSharedMemory.SectionLockInitialize: Failed to set mutex attribute type (%d).',[ThrErrorCode]);
        If not ErrChk(pthread_mutexattr_setrobust(@MutexAttr,PTHREAD_MUTEX_ROBUST)) then
          raise ESHMSMutexCreationError.CreateFmt('TSharedMemory.SectionLockInitialize: Failed to set mutex attribute robust (%d).',[ThrErrorCode]);
        If not ErrChk(pthread_mutex_init(Addr(PSharedMemoryHeader(fMemoryBase)^.SectionLock.PthreadMutex),@MutexAttr)) then
          raise ESHMSMutexCreationError.CreateFmt('TSharedMemory.SectionLockInitialize: Failed to init mutex (%d).',[ThrErrorCode]);
      finally
        pthread_mutexattr_destroy(@MutexAttr);
      end
    else raise ESHMSMutexCreationError.CreateFmt('TSharedMemory.SectionLockInitialize: Failed to init mutex attributes (%d).',[ThrErrorCode]);
  end
else SimpleRecursiveMutexInit(PSharedMemoryHeader(fMemoryBase)^.SectionLock.SimpleMutex);
end;
{$ENDIF}

//------------------------------------------------------------------------------

procedure TSharedMemory.SectionLockFinalize;
begin
{$IFDEF Windows}
CloseHandle(fMappingSync);
{$ELSE}
If not (optCrossArchitecture in fCreationOptions) then
  pthread_mutex_destroy(Addr(PSharedMemoryHeader(fMemoryBase)^.SectionLock.PthreadMutex)) // ignore errors
else
  SimpleRecursiveMutexInit(PSharedMemoryHeader(fMemoryBase)^.SectionLock.SimpleMutex);    // using init here is not an error
{$ENDIF}
end;

{-------------------------------------------------------------------------------
    TSharedMemory - public methods
-------------------------------------------------------------------------------}

Function TSharedMemory.Lock: Boolean;
{$IFDEF Windows}
begin
case WaitForSingleObject(fMappingSync,INFINITE) of
  WAIT_OBJECT_0:  Result := True;
  WAIT_ABANDONED: Result := False;
else
  raise ESHMSLockError.Create('TSharedMemory.Lock: Failed to lock.');
end;
end;
{$ELSE}
var
  ReturnValue:  cint;
begin
If not (optCrossArchitecture in fCreationOptions) then
  begin
    ReturnValue := pthread_mutex_lock(Addr(PSharedMemoryHeader(fMemoryBase)^.SectionLock.PthreadMutex));
    Result := True;
    If ReturnValue = ESysEOWNERDEAD then
      begin
        Result := False;
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
else Result := SimpleRecursiveMutexLock(PSharedMemoryHeader(fMemoryBase)^.SectionLock.SimpleMutex) in [lrSignaled,lrRelock];
end;
{$ENDIF}

//------------------------------------------------------------------------------

procedure TSharedMemory.Unlock;
begin
{$IFDEF Windows}
If not ReleaseMutex(fMappingSync) then
  raise ESHMSUnlockError.CreateFmt('TSharedMemory.Unlock: Failed to unlock (%d).',[GetLastError]);
{$ELSE}
If not (optCrossArchitecture in fCreationOptions) then
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

//------------------------------------------------------------------------------

procedure TSimpleSharedMemoryStream.Initialize;
begin
// nothing to do here
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
Initialize;
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

//------------------------------------------------------------------------------

procedure TSharedMemoryStream.Initialize;
begin
fFailOnAbandonedLock := False;
end;

{-------------------------------------------------------------------------------
    TSharedMemoryStream - public methods
-------------------------------------------------------------------------------}

Function TSharedMemoryStream.Lock: Boolean;
begin
Result := TSharedMemory(fSharedMemory).Lock;
end;

//------------------------------------------------------------------------------

procedure TSharedMemoryStream.Unlock;
begin
TSharedMemory(fSharedMemory).Unlock;
end;

//------------------------------------------------------------------------------

Function TSharedMemoryStream.Read(var Buffer; Count: LongInt): LongInt;
begin
If Lock or not fFailOnAbandonedLock then
  try
    Result := inherited Read(Buffer,Count);
  finally
    Unlock;
  end
else raise ESHMSConsistencyError.Create('TSharedMemoryStream.Read: Lock was abandoned, protected data might be damaged.');
end;

//------------------------------------------------------------------------------

Function TSharedMemoryStream.Write(const Buffer; Count: LongInt): LongInt;
begin
If Lock or not fFailOnAbandonedLock then
  try
    Result := inherited Write(Buffer,Count);
  finally
    Unlock;
  end
else raise ESHMSConsistencyError.Create('TSharedMemoryStream.Write: Lock was abandoned, protected data might be damaged.');
end;

//------------------------------------------------------------------------------

Function TSharedMemoryStream.ReadNoLock(var Buffer; Count: LongInt): LongInt;
begin
Result := inherited Read(Buffer,Count);
end;

//------------------------------------------------------------------------------

Function TSharedMemoryStream.WriteNoLock(const Buffer; Count: LongInt): LongInt;
begin
Result := inherited Write(Buffer,Count);
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
