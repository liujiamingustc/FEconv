module module_write_mphtxt
!-----------------------------------------------------------------------
! Module for mphtxt file read
! Last update: 07/02/2014
!-----------------------------------------------------------------------
use module_COMPILER_DEPENDANT, only: real64
use module_os_dependant, only: maxpath
use module_report, only:error
use module_convers
use module_ALLOC
use module_mesh
use module_pmh
contains

!***********************************************************************
! OUTPUT PROCEDURES
!***********************************************************************
!-----------------------------------------------------------------------
! write: write mphtxt file header
!-----------------------------------------------------------------------

subroutine write_mphtxt_header(iu, pmh)
  integer,                  intent(in)  :: iu ! File unit number
  type(pmh_mesh),           intent(in)  :: pmh  ! PMH mesh


  call write_comment(iu,'#','Converted with FEconv')
  call write_empty_line(iu)
  call write_comment(iu,'#','Major % minor version')
  call write_line(iu,   '0 1')
  call write_comment(iu,'#','number of tags')
  call write_line(iu,   string(size(pmh%pc,1)))
  call write_comment(iu,'#','Tags')
  do i=1, size(pmh%pc,1)
    call write_string(iu,   'mesh'//trim(string(i)))
  enddo
  call write_comment(iu,'#','Types')
  do i=1, size(pmh%pc,1)
    call write_string(iu,   'obj')
  enddo
  call write_empty_line(iu)
  
end subroutine


subroutine write_mphtxt_object(iu, pmh_o, n)
  integer,                  intent(in)  :: iu    ! File unit number
  type(piece),              intent(in)  :: pmh_o ! PMH piece
  integer,                  intent(in)  :: n     ! Piece number
  integer                               :: i
  character(len=MAXPATH)                :: aux  

  call write_comment(iu,'#','--------- Object '//trim(string(n))//' ----------')
  call write_empty_line(iu)
  call write_line(iu,   '0 0 1')
  call write_line(iu, 'Mesh',                    '#', 'class')
  call write_line(iu, '2',                       '#', 'version')
  call write_line(iu, string(pmh_o%dim),         '#', 'sdim')
  if(pmh_o%nver == 0) then                                                     ! z = nodes
    call write_line(iu, string(pmh_o%nnod),      '#', 'number of mesh points') ! nnod
    do i=1,pmh_o%nnod
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!      write_line(iu,string(pmh_o%z(:,i)))
    enddo
  else                                                                         ! z = vertices
    call write_line(iu, string(pmh_o%nver),      '#', 'number of mesh points') ! nver
    do i=1,pmh_o%nver
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!      write_line(iu,string(pmh_o%z(:,i)))
    enddo
  endif
  call write_line(iu, '1',                       '#', 'lowest mesh point index')
  call write_empty_line(iu)
  call write_comment(iu,                         '#', 'Mesh point coordinates')
  call write_empty_line(iu)
  call write_line(iu, string(size(pmh_o%el,1)),  '#', 'number of element types')

  do i=1, size(pmh_o%el,1)
    call write_mphtxt_etype(iu, pmh_o%el(i),i)
  enddo

  
end subroutine


subroutine write_mphtxt_etype(iu, pmh_t,n)
  integer,                  intent(in)  :: iu    ! File unit number
  type(elgroup),            intent(in)  :: pmh_o ! PMH elgroup
  integer,                  intent(in)  :: n     ! Piece number


end subroutine


subroutine write_line(iu,line,ch,comm)
  integer,                  intent(in)    :: iu   ! File unit number
  character(len=*),         intent(in)    :: line ! String
  character(len=*), optional, intent(in)  :: ch   ! String: Comment character
  character(len=*), optional, intent(in)  :: comm ! String: Comment
  character(len=MAXPATH)                  :: aux  

  if(present(comm)) then
    if(present(ch)) then
      aux = trim(ch)//' '//trim(comm)
    else
      aux = '# '//trim(comm)
    endif
  else
    aux = ''
  endif


  write(unit=iu, fmt='(a)', iostat = ios) trim(line)//' '//trim(aux)
  if (ios /= 0) call error('write_mphtxt/header, #'//trim(string(ios)))

end subroutine

subroutine write_comment(iu,ch,line)
  integer,                  intent(in)  :: iu   ! File unit number
  character(len=*),         intent(in)  :: ch   ! String: Comment character
  character(len=*),         intent(in)  :: line ! String

  call write_line(iu,trim(ch)//' '//trim(line))

end subroutine

subroutine write_empty_line(iu)
  integer,                  intent(in)  :: iu   ! File unit number

  call write_line(iu,'')

end subroutine

subroutine write_string(iu,str,comm)
  integer,                    intent(in)  :: iu   ! File unit number
  character(len=*),           intent(in)  :: str  ! String
  character(len=*), optional, intent(in)  :: comm ! String: Comment
  character(len=MAXPATH)                  :: aux  

  if(present(comm)) then
    aux = '# '//trim(comm)
  else
    aux = ''
  endif

  call write_line(iu,string(len_trim(str))//' '//trim(str),trim(aux))

end subroutine

!function mphtxt_get_type(num) result(res)
!
!  integer,     intent(in) :: num
!  character(len=MAXPATH)  :: res
!
!    res = ''
!
!    if((FEDB(i)%nver_eq_nnod .eqv. .true.) .and. (1==FEDB(i)%lnn) .and.     &                     ! Node
!        1==FEDB(i)%lnv) .and. (0==FEDB(i)%lne) .and. (0==FEDB(i)%lnf)) then
!      res = 'vtk'
!      call info('Element type: Node')
!    elseif((FEDB(i)%nver_eq_nnod .eqv. .true.) .and. (2==FEDB(i)%lnn) .and.     &                     ! Edge Lagrange P1
!        2==FEDB(i)%lnv) .and. (1==FEDB(i)%lne) .and. (0==FEDB(i)%lnf)) then
!      res = 'edg'
!      call info('Element type: Edge lagrange P1')
!    elseif((FEDB(i)%nver_eq_nnod .eqv. .true.) .and. (3==FEDB(i)%lnn) .and.     &                     ! Triangle Lagrange P1
!        3==FEDB(i)%lnv) .and. (3==FEDB(i)%lne) .and. (0==FEDB(i)%lnf)) then
!      res = 'tri'
!      call info('Element type: Triangle lagrange P1')
!    elseif((FEDB(i)%nver_eq_nnod .eqv. .true.) .and. (4==FEDB(i)%lnn) .and.     &                     ! Quadrangle Lagrange P1
!        4==FEDB(i)%lnv) .and. (4==FEDB(i)%lne) .and. (0==FEDB(i)%lnf)) then
!      res = 'quad'
!      call info('Element type: Quadrangle lagrange P1')
!    elseif((FEDB(i)%nver_eq_nnod .eqv. .true.) .and. (4==FEDB(i)%lnn) .and.     &                     ! Tetrahedron Lagrange P1
!        4==FEDB(i)%lnv) .and. (6==FEDB(i)%lne) .and. (4==FEDB(i)%lnf)) then
!      res = 'tet'
!      call info('Element type: Tetrahedron lagrange P1')
!    elseif((FEDB(i)%nver_eq_nnod .eqv. .true.) .and. (8==FEDB(i)%lnn) .and.     &                     ! Hexahedron Lagrange P1
!        8==FEDB(i)%lnv) .and. (12==FEDB(i)%lne) .and. (6==FEDB(i)%lnf)) then
!      res = 'hex'
!      call info('Element type: Hexahedron lagrange P1')
!    elseif((FEDB(i)%nver_eq_nnod .eqv. .false.) .and. (3==FEDB(i)%lnn) .and.     &                    ! Edge Lagrange P2
!        2==FEDB(i)%lnv) .and. (1==FEDB(i)%lne) .and. (0==FEDB(i)%lnf)) then
!      res = 'edg2'
!      call info('Element type: Edge lagrange P2')
!    elseif((FEDB(i)%nver_eq_nnod .eqv. .false.) .and. (6==FEDB(i)%lnn) .and.     &                    ! Triangle Lagrange P2
!        3==FEDB(i)%lnv) .and. (3==FEDB(i)%lne) .and. (0==FEDB(i)%lnf)) then
!      res = 'tri2'
!      call info('Element type: Triangle lagrange P2')
!    elseif((FEDB(i)%nver_eq_nnod .eqv. .false.) .and. (9==FEDB(i)%lnn) .and.     &                    ! Quadrangle Lagrange P2
!        4==FEDB(i)%lnv) .and. (4==FEDB(i)%lne) .and. (0==FEDB(i)%lnf)) then
!      res = 'quad2'
!      call info('Element type: Quadrangle lagrange P2')
!    elseif((FEDB(i)%nver_eq_nnod .eqv. .false.) .and. (10==FEDB(i)%lnn) .and.     &                   ! Tetrahedron Lagrange P2
!        4==FEDB(i)%lnv) .and. (4==FEDB(i)%lne) .and. (4==FEDB(i)%lnf)) then
!      res = 'tet2'
!      call info('Element type: Tetrahedron lagrange P2')
!    elseif((FEDB(i)%nver_eq_nnod .eqv. .false.) .and. (26==FEDB(i)%lnn) .and.     &                     ! Hexahedron Lagrange P2
!        8==FEDB(i)%lnv) .and. (8==FEDB(i)%lne) .and. (6==FEDB(i)%lnf)) then
!      res = 'hex2'
!      call info('Element type: Hexahedron lagrange P2')
!    else
!      call error('Finite element type not supported')
!  endif
!
!
!end function

end module
