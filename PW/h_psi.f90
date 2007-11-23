!
! Copyright (C) 2002-2007 Quantum-ESPRESSO group
! This file is distributed under the terms of the
! GNU General Public License. See the file `License'
! in the root directory of the present distribution,
! or http://www.gnu.org/copyleft/gpl.txt .
!
!----------------------------------------------------------------------------
SUBROUTINE h_psi( lda, n, m, psi, hpsi )
  !----------------------------------------------------------------------------
  !
  ! ... This routine computes the product of the Hamiltonian
  ! ... matrix with m wavefunctions contained in psi
  !
  ! ... input:
  ! ...    lda   leading dimension of arrays psi, spsi, hpsi
  ! ...    n     true dimension of psi, spsi, hpsi
  ! ...    m     number of states psi
  ! ...    psi
  !
  ! ... output:
  ! ...    hpsi  H*psi
  !
  USE kinds,    ONLY : DP
  USE uspp,     ONLY : vkb, nkb
  USE wvfct,    ONLY : igk, g2kin
  USE gsmooth,  ONLY : nls, nr1s, nr2s, nr3s, nrx1s, nrx2s, nrx3s, nrxxs
  USE ldaU,     ONLY : lda_plus_u
  USE lsda_mod, ONLY : current_spin
  USE scf,      ONLY : vrs  
  USE gvect,    ONLY : gstart
#ifdef EXX
  USE exx,      ONLY : vexx
  USE funct,    ONLY : exx_is_active
#endif
  USE funct,    ONLY : dft_is_meta
  USE bp,       ONLY : lelfield
  USE control_flags,    ONLY : gamma_only
  USE noncollin_module, ONLY: npol, noncolin
  !
  IMPLICIT NONE
  !
  ! ... input/output arguments
  !
  INTEGER     :: lda, n, m
  COMPLEX(DP) :: psi(lda*npol,m) 
  COMPLEX(DP) :: hpsi(lda*npol,m)   
  !
  !
  CALL start_clock( 'h_psi' )
  !  
  IF ( gamma_only ) THEN
     !
     CALL h_psi_gamma( )
     !
  ELSE IF ( noncolin ) THEN
     !
     ! ... Unlike h_psi_gamma and h_psi_k, this is an external routine
     !
     CALL h_psi_nc( lda, n, m, psi, hpsi )
     !
  ELSE  
     !
     CALL h_psi_k( )
     !
  END IF  
  !
  ! ... electric enthalpy if required
  !
  IF ( lelfield ) CALL h_epsi_her_apply( lda, n, m, psi, hpsi )
  !
  CALL stop_clock( 'h_psi' )
  !
  RETURN
  !
  CONTAINS
     !
     !-----------------------------------------------------------------------
     SUBROUTINE h_psi_gamma( )
       !-----------------------------------------------------------------------
       ! 
       ! ... gamma version
       !
       USE becmod,  ONLY : rbecp
       !
       IMPLICIT NONE
       !
       INTEGER :: ibnd, j
       !
       !
       CALL start_clock( 'h_psi:init' )
       !
       ! ... Here we apply the kinetic energy (k+G)^2 psi
       !
       DO ibnd = 1, m
          !
          ! ... set to zero the imaginary part of psi at G=0
          ! ... absolutely needed for numerical stability
          !
          IF ( gstart == 2 ) psi(1,ibnd) = CMPLX( DBLE( psi(1,ibnd) ), 0.D0 )
          !
          hpsi(1:n,ibnd) = g2kin(1:n) * psi(1:n,ibnd)
          !
       END DO
       !
       CALL stop_clock( 'h_psi:init' )
        
       if (dft_is_meta()) call h_psi_meta (lda, n, m, psi, hpsi)
       !
       ! ... Here we add the Hubbard potential times psi
       !
       IF ( lda_plus_u ) CALL vhpsi( lda, n, m, psi, hpsi )
       !
       ! ... the local potential V_Loc psi
       !
       CALL vloc_psi( lda, n, m, psi, vrs(1,current_spin), hpsi )
       !
       ! ... Here the product with the non local potential V_NL psi
       !
       IF ( nkb > 0 ) THEN
          !
          CALL pw_gemm( 'Y', nkb, m, n, vkb, lda, psi, lda, rbecp, nkb )
          !
          CALL add_vuspsi( lda, n, m, psi, hpsi )
          !
       END IF
       !
#ifdef EXX
       IF ( exx_is_active() ) CALL vexx( lda, n, m, psi, hpsi )
#endif
       !
       RETURN
       !
     END SUBROUTINE h_psi_gamma
     !
     !
     !-----------------------------------------------------------------------
     SUBROUTINE h_psi_k( )
       !-----------------------------------------------------------------------
       !
       ! ... k-points version
       !
       USE wavefunctions_module, ONLY : psic
       USE becmod,               ONLY : becp
       !
       IMPLICIT NONE
       !
       INTEGER :: ibnd, j
       ! counters
       !
       !
       CALL start_clock( 'h_psi:init' )
       !
       ! ... Here we apply the kinetic energy (k+G)^2 psi
       !
       DO ibnd = 1, m
          !
          hpsi(1:n,ibnd) = g2kin(1:n) * psi(1:n,ibnd)
          !
       END DO
       !
       CALL stop_clock( 'h_psi:init' )
        
       if (dft_is_meta()) call h_psi_meta (lda, n, m, psi, hpsi)
       !
       ! ... Here we add the Hubbard potential times psi
       !
       IF ( lda_plus_u ) CALL vhpsi( lda, n, m, psi, hpsi )
       !
       ! ... the local potential V_Loc psi. First the psi in real space
       !
       DO ibnd = 1, m
          !
          CALL start_clock( 'h_psi:firstfft' )
          !
          psic(1:nrxxs) = ( 0.D0, 0.D0 )
          !
          psic(nls(igk(1:n))) = psi(1:n,ibnd)
          !
          CALL cft3s( psic, nr1s, nr2s, nr3s, nrx1s, nrx2s, nrx3s, 2 )
          !
          CALL stop_clock( 'h_psi:firstfft' )
          !
          ! ... product with the potential vrs = (vltot+vr) on the smooth grid
          !
          psic(1:nrxxs) = psic(1:nrxxs) * vrs(1:nrxxs,current_spin)
          !
          ! ... back to reciprocal space
          !
          CALL start_clock( 'h_psi:secondfft' )
          !
          CALL cft3s( psic, nr1s, nr2s, nr3s, nrx1s, nrx2s, nrx3s, -2 )
          !
          ! ... addition to the total product
          !
          hpsi(1:n,ibnd) = hpsi(1:n,ibnd) + psic(nls(igk(1:n)))
          !
          CALL stop_clock( 'h_psi:secondfft' )
          !
       END DO
       !
       ! ... Here the product with the non local potential V_NL psi
       !
       IF ( nkb > 0 ) THEN
          !
          CALL ccalbec( nkb, lda, n, m, becp, vkb, psi )
          !
          CALL add_vuspsi( lda, n, m, psi, hpsi )
          !
       END IF
       !
#ifdef EXX
       IF ( exx_is_active() ) CALL vexx( lda, n, m, psi, hpsi )
#endif
       !
       RETURN
       !
     END SUBROUTINE h_psi_k     
     !
END SUBROUTINE h_psi
!
!-----------------------------------------------------------------------
subroutine h_psi_nc (lda, n, m, psi, hpsi)
  !-----------------------------------------------------------------------
  !
  !     This routine computes the product of the Hamiltonian
  !     matrix with m wavefunctions contained in psi
  ! input:
  !     lda   leading dimension of arrays psi, hpsi
  !     n     true dimension of psi, hpsi
  !     m     number of states psi
  !     psi
  ! output:
  !     hpsi  H*psi
  !
  use uspp, only: vkb, nkb
  use wvfct, only: igk, g2kin
  use gsmooth, only : nls, nr1s, nr2s, nr3s, nrx1s, nrx2s, nrx3s, nrxxs
  use ldaU, only : lda_plus_u
  use lsda_mod, only : current_spin
  use scf, only: vrs
  use becmod
  use wavefunctions_module, only: psic_nc
  use noncollin_module, only: noncolin, npol
  implicit none
  !
  integer :: lda, n, m
  complex(DP) :: psi(lda,npol,m), hpsi(lda,npol,m),&
                      sup, sdwn
  !
  integer :: ibnd,j,ipol
  ! counters
  call start_clock ('h_psi')
  call start_clock ('h_psi:init')
  call ccalbec_nc (nkb, lda, n, npol, m, becp_nc, vkb, psi)
  !
  ! Here we apply the kinetic energy (k+G)^2 psi
  !
  do ibnd = 1, m
     do ipol = 1, npol
        do j = 1, n
           hpsi (j, ipol, ibnd) = g2kin (j) * psi (j, ipol, ibnd)
        enddo
     enddo
  enddo

  call stop_clock ('h_psi:init')
  !
  ! Here we add the Hubbard potential times psi
  !
  if (lda_plus_u) call vhpsi_nc (lda, n, m, psi(1,1,1), hpsi(1,1,1))
  !
  ! the local potential V_Loc psi. First the psi in real space
  !
  do ibnd = 1, m
     call start_clock ('h_psi:firstfft')
     psic_nc = (0.d0,0.d0)
     do ipol=1,npol
        do j = 1, n
           psic_nc(nls(igk(j)),ipol) = psi(j,ipol,ibnd)
        enddo
        call cft3s (psic_nc(1,ipol), nr1s, nr2s, nr3s, nrx1s, nrx2s, nrx3s, 2)
     enddo
     call stop_clock ('h_psi:firstfft')
     !
     !   product with the potential vrs = (vltot+vr) on the smooth grid
     !
     if (noncolin) then
        do j=1, nrxxs
           sup = psic_nc(j,1) * (vrs(j,1)+vrs(j,4)) + &
                 psic_nc(j,2) * (vrs(j,2)-(0.d0,1.d0)*vrs(j,3))
           sdwn = psic_nc(j,2) * (vrs(j,1)-vrs(j,4)) + &
                  psic_nc(j,1) * (vrs(j,2)+(0.d0,1.d0)*vrs(j,3))
           psic_nc(j,1)=sup
           psic_nc(j,2)=sdwn
        end do
     else
        do j = 1, nrxxs
           psic_nc(j,1) = psic_nc(j,1) * vrs(j,current_spin)
        enddo
     endif
     !
     !   back to reciprocal space
     !
     call start_clock ('h_psi:secondfft')
     do ipol=1,npol
        call cft3s (psic_nc(1,ipol), nr1s, nr2s, nr3s, nrx1s, nrx2s, nrx3s, -2)
     enddo
     !
     !   addition to the total product
     !
     do ipol=1,npol
        do j = 1, n
           hpsi(j,ipol,ibnd) = hpsi(j,ipol,ibnd) + psic_nc(nls(igk(j)),ipol)
        enddo
     enddo
     call stop_clock ('h_psi:secondfft')
  enddo
  !
  !  Here the product with the non local potential V_NL psi
  !
  if (nkb.gt.0) call add_vuspsi_nc (lda, n, m, psi, hpsi(1,1,1))
  call stop_clock ('h_psi')
  return
end subroutine h_psi_nc
