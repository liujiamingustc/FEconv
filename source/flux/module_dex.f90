module module_dex
!-----------------------------------------------------------------------
! Module to manage MFF (Modulef Formatted Field) files
!
! Licensing: This code is distributed under the GNU GPL license.
! Author: Víctor Sande, victor(dot)sande(at)usc(dot)es
! Last update: 19/05/2014
!
! PUBLIC PROCEDURES:
!   load_mff: loads a mesh from a MFM format file
!   save_mff: saves a mesh in a MFM format file
!-----------------------------------------------------------------------
use module_compiler_dependant, only: real64
use module_files, only: get_unit
use module_convers, only: string, replace
use module_report, only:error
use module_pmh

implicit none!

!type field
!  character(maxpath)        :: name 
!  real(real64), allocatable :: param(:)   !nshot
!  real(real64), allocatable :: val(:,:,:) !ncomp x nnod x nshot
!end type
!private :: field

contains

subroutine load_dex(pmh, filenames, fieldnames, param)
  character(len=*), allocatable, intent(in) :: filenames(:) !fields file names
  type(pmh_mesh),             intent(inout) :: pmh
  character(*), allocatable,     intent(in) :: fieldnames(:) !field names
  real(real64), optional,        intent(in) :: param 
  character(len=maxpath)                    :: filename, fieldname, aux
  integer                                   :: nb_real, nb_comp, nb_point
  integer                                   :: iu, ios, i, j, k, idx
  real(real64), allocatable                 :: coords(:,:), vals(:,:)
  type(field), allocatable                  :: tempfields(:)
!  integer                                   :: ncomp, totcomp, maxtdim



  if(size(filenames,1) /= size(fieldnames,1)) &
    call error('load_dex/ Filenames and fieldnames dimension must agree')

  do j=1, size(filenames,1)
    filename = trim(filenames(j))
    fieldname = trim(fieldnames(j))
    iu = get_unit()
    !open file

    open (unit=iu, file=filename, form='formatted', status='old', position='rewind', iostat=ios)
    if (ios /= 0) call error('load/open, #'//trim(string(ios)))
  
    !try read field name
    read(unit=iu, fmt=*, iostat=ios) aux,aux,aux,aux,aux,aux,aux
    if (ios /= 0) call error('load/open, #'//trim(string(ios)))
    !try read number of real, number of components and number of points
    read(unit=iu, fmt=*, iostat=ios) aux,aux,nb_real,aux,aux,nb_comp,aux,aux,nb_point
    if (ios /= 0) call error('load/open, #'//trim(string(ios)))  

    if(size(pmh%pc,1) == 1) then
      if(pmh%pc(1)%nnod /= nb_point) then
        call info('Number of values in field must agree with number of nodes. Skipped!')
      else
        if(allocated(coords)) deallocate(coords)
        if(allocated(vals)) deallocate(vals)
        allocate(coords(pmh%pc(1)%dim,nb_point))
        allocate(vals(nb_comp,nb_point))
        ! Read coords and values
        do i=1,nb_point
          read(unit=iu, fmt=*, iostat=ios) coords(:,i),vals(:,i)
          if (ios /= 0) call error('load/open, #'//trim(string(ios)))  
        enddo
        if(.not. allocated(pmh%pc(1)%fi)) then 
          allocate(pmh%pc(1)%fi(1))
        else
          if(allocated(tempfields)) deallocate(tempfields)
          allocate(tempfields(size(pmh%pc(1)%fi,1)+1))
          tempfields(1:size(pmh%pc(1)%fi,1)) = pmh%pc(1)%fi(:)
          call move_alloc(from=tempfields, to=pmh%pc(1)%fi)
        endif
        idx = size(pmh%pc(1)%fi,1)
        call info('Reading node field from: '//trim(adjustl(filenames(j))))
        pmh%pc(1)%fi(idx)%name = trim(filename)
        if(allocated(pmh%pc(1)%fi(idx)%param)) deallocate(pmh%pc(1)%fi(idx)%param)
        allocate(pmh%pc(1)%fi(idx)%param(1))      
        if(present(param)) then 
          pmh%pc(1)%fi(idx)%param(1) = param
        else
          pmh%pc(1)%fi(idx)%param(1) = 0._real64
        endif
        if(allocated(pmh%pc(1)%fi(idx)%val)) deallocate(pmh%pc(1)%fi(idx)%val)
        allocate(pmh%pc(1)%fi(idx)%val(nb_comp, nb_point,1))
        pmh%pc(1)%fi(idx)%val(:,:,1) = vals(:,:)

      endif
    endif

    close(iu)

  enddo
  print*, ''

end subroutine


subroutine save_dex(pmh, infield, outfield, path, param)
  type(pmh_mesh),            intent(inout) :: pmh      !PMH mesh
  character(*), allocatable, intent(in) :: infield(:)  ! In field names
  character(*), allocatable, intent(in) :: outfield(:) ! Out field names
  character(*),              intent(in) :: path !file names
  real(real64), optional,    intent(in) :: param 
  character(len=maxpath)                :: filename !file names
  integer                               :: i,j,k,l,m,pi,mtdim
  integer                               :: iu, ios, fidx
  logical                               :: all_f

  if(size(infield,1) /= size(outfield,1)) &
    call error('load_mff/ Filenames and fieldnames dimension must agree')

  all_f = .false.

  if(size(infield,1) == 1) all_f = (trim(infield(1)) == '*')
  if(size(infield,1) == 1 .and. size(outfield,1) == 1) all_f = .true.

  do fidx=1, size(infield,1)
    filename = trim(path)//trim(outfield(fidx))

    pi = 1
    mtdim = 0

    do i=1, size(pmh%pc,1)
      ! Point data
      if(allocated(pmh%pc(i)%fi)) then
        do j=1, size(pmh%pc(i)%fi,1)
          if(trim(infield(fidx)) == trim(pmh%pc(i)%fi(j)%name) .or. all_f) then
            if(.not. allocated(pmh%pc(i)%fi(j)%val)) &
               &call error("save_mff/ Point field "//trim(infield(fidx))//": not allocated")
            call fix_filename(pmh%pc(i)%fi(j)%name)
            if(all_f .and. trim(infield(1)) == '*') &
              & filename = trim(path)//trim(outfield(1))//'__'//trim(pmh%pc(i)%fi(j)%name)//'.mff'
            call info('Writing node field to: '//trim(adjustl(filename)))
            if(present(param)) then
              do k=1, size(pmh%pc(i)%fi(j)%param,1)
                if((pmh%pc(i)%fi(j)%param(k)-param)<pmh%ztol) pi = k
              enddo
            endif
            iu = get_unit() 
            open (unit=iu, file=trim(filename), form='formatted', position='rewind', iostat=ios)
            if (ios /= 0) call error('save/open, #'//trim(string(ios)))
            write(unit=iu, fmt=*, iostat = ios) size(pmh%pc(i)%z,2)*size(pmh%pc(i)%fi(j)%val,1)
            if (ios /= 0) call error('save_mff/header, #'//trim(string(ios)))
            do k=1,size(pmh%pc(i)%fi(j)%val,2)
  !            do l=1,size(pmh%pc(i)%fi(j)%val,1)
                write(unit=iu, fmt=*, iostat = ios) &
                  & (pmh%pc(i)%fi(j)%val(l,k,pi), l=1, size(pmh%pc(i)%fi(j)%val,1) )
                if (ios /= 0) call error('save_mff/header, #'//trim(string(ios)))
  !            enddo
            enddo
            close(iu)
          endif
        enddo
      endif
      ! Cell data
      do j=1, size(pmh%pc(i)%el,1)
        mtdim = max(FEDB(pmh%pc(i)%el(j)%type)%tdim,mtdim)
      enddo
      do j=1, size(pmh%pc(i)%el,1)
        if(mtdim == FEDB(pmh%pc(i)%el(j)%type)%tdim .and. allocated(pmh%pc(i)%el(j)%fi)) then
          do k=1,size(pmh%pc(i)%el(j)%fi,1)
            if(trim(infield(fidx)) == trim(pmh%pc(i)%el(j)%fi(k)%name)) then
              if(.not. allocated(pmh%pc(i)%el(j)%fi(k)%val)) &
                & call error("save_mff/ Cell field "//trim(infield(fidx))//": not allocated")
              call fix_filename(pmh%pc(i)%el(j)%fi(k)%name)
              if(all_f .and. trim(infield(1)) == '*') &
                & filename = trim(path)//trim(outfield(1))//'__'//trim(pmh%pc(i)%el(j)%fi(k)%name)//'.mff'
            call info('Writing cell field to: '//trim(adjustl(filename)))
              if(present(param)) then
                do l=1, size(pmh%pc(i)%el(j)%fi(l)%param,1)
                  if((pmh%pc(i)%el(j)%fi(k)%param(l)-param)<pmh%ztol) pi = k
                enddo
              endif
              ! write pmh%pc(i)%el(j)%nel
              do l=1,size(pmh%pc(i)%el(j)%fi(k)%val,2)
                do m=1,size(pmh%pc(i)%el(j)%fi(k)%val,1)
                  !write pmh%pc(i)%el(j)%fi(k)%val(l,k,pi)
                enddo
              enddo            
            endif
          enddo
        endif
      enddo
    enddo

  
  enddo
end subroutine

subroutine fix_filename(filename)
  character(len=*), intent(inout) :: filename !file names
  character(1), dimension(9)      ::  chars = ['<','>',':','"','/','\','|','?','*']
  integer                         :: i

  do i=1, size(chars,1)
    call replace(filename,chars(i),'_')
  enddo

end subroutine

end module
