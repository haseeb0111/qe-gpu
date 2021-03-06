!
! Copyright (C) 2001-2013 Quantum ESPRESSO group
! This file is distributed under the terms of the
! GNU General Public License. See the file `License'
! in the root directory of the present distribution,
! or http://www.gnu.org/copyleft/gpl.txt .
!
!----------------------------------------------------------------------------
PROGRAM pwscf
  !! author: Paolo Giannozzi
  !! version: v6.0
  !! license: GNU 
  !! summary: Main program calling one instance of Plane Wave Self-Consistent Field code
  !!
  !! This is the main program that calls [[run_driver]].
  !!
  !! @Note
  !! 10/01/17 Samuel Ponce: Add Ford documentation
  !! @endnote
  !!
  !! @warning
  !! Example of Warning
  !!
  !! @todo
  !! Have automatic parallelisation. 
  !!
  !! @bug
  !! No bug.
  !!
  USE environment,       ONLY : environment_start
  USE mp_global,         ONLY : mp_startup
  USE read_input,        ONLY : read_input_file
  USE command_line_options, ONLY: input_file_, command_line
  !
#ifdef USE_CUDA
!  USE mpiDeviceUtil, ONLY : assignDevice
  USE mpiDeviceUtil, ONLY : assignDevice
  USE gpu_routines, ONLY : setupCublasHandle
  USE eigsolve_vars, ONLY: init_eigsolve_gpu
#endif
  !
  IMPLICIT NONE
  CHARACTER(len=256) :: srvaddress
  !! Get the address of the server 
  CHARACTER(len=256) :: get_server_address
  !! Get the address of the server 
  INTEGER :: dev
  INTEGER :: exit_status
  !! Status at exit
  !
  !
  CALL mp_startup ( diag_in_band_group = .true. )

#ifdef USE_CUDA
  ! This routine assigns a different GPU to each MPI rank in the same server
  CALL assignDevice( dev )
  CALL setupCublasHandle()
  CALL init_eigsolve_gpu()
#if defined(__GPU_DEBUG)
  print *,"Running on GPU dev = ",dev
#endif
#endif
  !
  CALL environment_start ( 'PWSCF' )
  !
  CALL read_input_file ('PW', input_file_ )
  !
  ! ... Check if running standalone or in "driver" mode
  !
  srvaddress = get_server_address ( command_line ) 
  !
  ! ... Perform actual calculation
  !
  IF ( trim(srvaddress) == ' ' ) THEN
     CALL run_pwscf  ( exit_status )
  ELSE
     CALL run_driver ( srvaddress, exit_status )
  END IF
  !
  CALL stop_run( exit_status )
  !CALL do_stop( exit_status )
  !
  STOP
  !
END PROGRAM pwscf

FUNCTION get_server_address ( command_line ) RESULT ( srvaddress )
  ! 
  ! checks for the presence of a command-line option of the form
  ! -server_ip "srvaddress" or --server_ip "srvaddress";
  ! returns "srvaddress", used to run pw.x in driver mode.
  ! On input, "command_line" must contain the unprocessed part of the command
  ! line, on all processors, as returned after a call to "get_cammand_line"
  !
  USE command_line_options, ONLY : my_iargc, my_getarg
  IMPLICIT NONE
  CHARACTER(LEN=*), INTENT(IN) :: command_line
  CHARACTER(LEN=256) :: srvaddress
  !
  INTEGER  :: nargs, narg
  CHARACTER (len=320) :: arg
  !
  srvaddress = ' '
  IF ( command_line == ' ' ) RETURN
  !
  nargs = my_iargc ( command_line )
  !
  narg = 0
10 CONTINUE
  CALL my_getarg ( command_line, narg, arg )
  IF ( TRIM (arg) == '-ipi' .OR. TRIM (arg) == '--ipi' ) THEN
     IF ( srvaddress == ' ' ) THEN
        narg = narg + 1
        IF ( narg > nargs ) THEN
           CALL infomsg('get_server_address','missing server IP in command line')
           RETURN
        ELSE
           CALL my_getarg ( command_line, narg, srvaddress )
        END IF
     ELSE
        CALL infomsg('get_server_address','duplicated server IP in command line')
     END IF
  END IF
  narg = narg + 1
  IF ( narg > nargs ) RETURN
  GO TO 10
  !
END FUNCTION get_server_address
