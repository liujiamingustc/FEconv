module module_feconv
!-----------------------------------------------------------------------
! Module to convert between several mesh and FE field formats
!
! Licensing: This code is distributed under the GNU GPL license.
! Author: Francisco Pena, fran(dot)pena(at)usc(dot)es
! Last update: 10/05/2013
!
! PUBLIC PROCEDURES:
! convert: converts between several mesh and FE field formats
! is_arg: returns true when the argument is present
!-----------------------------------------------------------------------
use module_compiler_dependant, only: real64
use module_os_dependant, only: maxpath, slash
use module_report, only: error
use module_convers, only: adjustlt, lcase, word_count
use module_files, only: get_unit
use module_alloc, only: set
use module_args, only: get_arg, is_arg, get_post_arg, args_count, set_args
use module_transform, only: lagr2l2, lagr2rt, lagr2nd, to_l1
use module_cuthill_mckee, only: cuthill_mckee
use module_msh, only: load_msh,save_msh
use module_unv, only: load_unv,save_unv
use module_patran, only: load_patran
use module_mfm, only: load_mfm, save_mfm
use module_mum, only: load_mum, save_mum
use module_vtu, only: load_vtu, save_vtu, type_cell
use module_pvd, only: load_pvd, save_pvd
use module_mphtxt, only: load_mphtxt,save_mphtxt
use module_pf3, only: load_pf3,save_pf3
!use module_tra, only: load_tra,save_tra
use module_field_database, only: FLDB, id_mesh_ext, id_field_ext
use module_mff, only: load_mff, save_mff
use module_muf, only: load_muf, save_muf
use module_freefem, only: save_freefem_msh, save_freefem_mesh, load_freefem_msh, load_freefem_mesh
use module_pmh
use module_fem_extract, only: extract_mesh, extract_ref
use module_gmsh, only: load_gmsh, save_gmsh
use module_dex, only: load_dex, save_dex
use module_ip, only: load_ip, save_ip
implicit none

!PMH structure
type(pmh_mesh) :: pmh

!Variables for MFM format
integer :: nel  = 0 !global number of elements
integer :: nnod = 0 !global number of nodes
integer :: nver = 0 !global number of vertices
integer :: dim  = 0 !space dimension
integer :: lnn  = 0 !local number of nodes
integer :: lnv  = 0 !local number of vertices
integer :: lne  = 0 !local number of edges
integer :: lnf  = 0 !local number of faces
integer, allocatable, dimension(:,:) :: nn  !nodes index array
integer, allocatable, dimension(:,:) :: mm  !vertices index array
integer, allocatable, dimension(:,:) :: nrv !vertices reference array
integer, allocatable, dimension(:,:) :: nra !edge reference array
integer, allocatable, dimension(:,:) :: nrc !face reference array
real(real64), allocatable, dimension(:,:) :: z !vertices coordinates array
integer, allocatable, dimension(:) :: nsd !subdomain index array

logical :: is_pmh !true if the working mesh is PMH, false if is MFM

contains

!-----------------------------------------------------------------------
! convert: converts between several mesh and FE field formats
!-----------------------------------------------------------------------
subroutine convert(cad,mempmh)
character(*),   optional, intent(in)    :: cad
type(pmh_mesh), optional, intent(inout) :: mempmh
character(maxpath) :: infile=' ', inmesh=' ', inext=' ', outfile=' ', outmesh=' ', outext=' '
character(maxpath) :: infext=' ', outfext=' ', outpath = ' '!,fieldfilename = ' '
character(maxpath), allocatable :: infieldfile(:), outfieldfile(:),infieldname(:), outfieldname(:)
character(maxpath) :: str
integer :: p, nargs, q, comp
integer, allocatable :: nsd0(:)
logical :: there_is_field
!Variables for extratction
integer,      allocatable :: submm(:,:), subnrv(:,:), subnra(:,:), subnrc(:,:), subnsd(:), globv(:), globel(:)
real(real64), allocatable :: subz(:,:)
real(real64)              :: padval

if(present(cad)) then
  call set_args(cad)
else
  call info('String options for convert not found. Reading options from command line')
endif

!find infile and outfile at the end of the arguments
nargs = args_count()

if(is_arg('-l')) then
  infile = get_post_arg('-l')
  p = index( infile, '.', back=.true.)
  inmesh =  infile(1:p-1)
  inext =  lcase(infile(p+1:len_trim( infile)))
elseif(present(mempmh)) then
  infile = get_arg(nargs)
  p = index(infile, '.', back=.true.)
  inmesh = infile(1:p-1)
  inext = lcase(infile(p+1:len_trim(infile)))
else
  infile = get_arg(nargs-1); p = index( infile, '.', back=.true.); &
      & inmesh =  infile(1:p-1);  inext =  lcase(infile(p+1:len_trim( infile)))
  outfile = get_arg(nargs);  p = index(outfile, '.', back=.true.); &
      & outmesh = outfile(1:p-1); outext = lcase(outfile(p+1:len_trim(outfile)))
  p = index(outfile, slash(), back=.true.); outpath = outfile(1:p)
endif

!check mesh names and extensions
if (len_trim(infile)  == 0) call error('(module_feconv/fe_conv) unable to find input file.')
if (len_trim(inext)   == 0) call error('(module_feconv/fe_conv) unable to find input file extension.')
if(.not. is_arg('-l') .and. .not. present(mempmh)) then
  if (len_trim(outfile) == 0) call error('(module_feconv/fe_conv) unable to find output file.')
  if (len_trim(outext)  == 0) call error('(module_feconv/fe_conv) unable to find output file extension.')
  select case (trim(adjustlt(outext))) !check outfile extension now (avoid reading infile when outfile is invalid)
  case('mfm', 'mum', 'vtu', 'mphtxt', 'unv', 'pf3', 'msh', 'mesh', 'pmh', 'pvd')
    continue
  case default
    call error('(module_feconv/fe_conv) output file extension not implemented: '//trim(adjustlt(outext)))
  end select
endif

!check isoparametric option, for UNV only
!if (trim(adjustlt(inext)) /= 'unv' .and. is_arg('-is')) call error('(module_feconv/fe_conv) only UNV input files can '//&
!&'manage -is option.')
!options for mesh transformation (-l1, -l2, -rt, -nd and -cm) are incompatible with fields (-if, -of)
if ( (is_arg('-l1') .or. is_arg('-l2') .or. is_arg('-rt') .or. is_arg('-nd') .or. is_arg('-cm')) .and. &
     (is_arg('-if') .or. is_arg('-of')) ) call error('(module_feconv/fe_conv) options for mesh transformation (-l1, -l2, '//&
     &'-rt, -nd and -cm) are incompatible with fields (-if, -of).')
!set PMH mesh tolerance (all load procedures must consider intent(inout) for PMH argument)
if (is_arg('-t')) then 
  pmh%ztol = dble(get_post_arg('-t'))
end if    

!field selection
there_is_field = .true.
if(is_arg('-l') .or. present(mempmh)) then
  if (is_arg('-if')) then
    !there is -if
    str = get_post_arg('-if')
    p = index(str, '[')
    if (p == 0) then !a single field name
      call set(infieldfile, str, 1, fit=.true.)
    else !several subdomain refs. enclosed in [] and separated by ,
      q = index(str, ']', back=.true.)
      call alloc(infieldfile, word_count(str(p+1:q-1),','))
      read(str(p+1:q-1),*) infieldfile
    end if
    p = index( infieldfile(1), '.', back=.true.)
    infext =  infieldfile(1)(p+1:len_trim( infieldfile(1)))
  else
    there_is_field = .false.
  end if
else
  if (FLDB(id_mesh_ext(inext))%is_field_outside) then
    if (FLDB(id_mesh_ext(outext))%is_field_outside) then
      !infieldfile and outfieldfile are both mesh external
      if (.not. is_arg('-if') .and. is_arg('-of')) then
        call error('(module_feconv/fe_conv) option -if is mandatory to read external fields')
      elseif (.not. is_arg('-if')) then
        !there is not -if, there is not -of
        there_is_field = .false.
      elseif (is_arg('-if') .or. is_arg('-of')) then
        !there is -if
        if (is_arg('-if')) then
          str = get_post_arg('-if')
          p = index(str, '[')
          if (p == 0) then !a single field name
            call set(infieldfile, str, 1, fit=.true.)
          else !several subdomain refs. enclosed in [] and separated by ,
            q = index(str, ']', back=.true.)
            call alloc(infieldfile, word_count(str(p+1:q-1),','))
            read(str(p+1:q-1),*) infieldfile
          endif
          p = index( infieldfile(1), '.', back=.true.)
          infext =  infieldfile(1)(p+1:len_trim( infieldfile(1)))
          ! There is in and field extension is 'ip'
          if (id_field_ext(infext) == id_field_ext('ip') .and. is_arg('-in')) then
            str = get_post_arg('-in')
            p = index(str, '[')
            if (p == 0) then !a single field name
              call set(infieldname, str, 1, fit=.true.)
            else !several subdomain refs. enclosed in [] and separated by ,
              q = index(str, ']', back=.true.)
              call alloc(infieldname, word_count(str(p+1:q-1),','))
              read(str(p+1:q-1),*) infieldname
            end if
          endif
        endif
        if (is_arg('-of')) then
          str = get_post_arg('-of')
          p = index(str, '[')
          if (p == 0) then !a single field name
            call set(outfieldfile, str, 1, fit=.true.)
          else !several subdomain refs. enclosed in [] and separated by ,
            q = index(str, ']', back=.true.)
            call alloc(outfieldfile, word_count(str(p+1:q-1),','))
            read(str(p+1:q-1),*) outfieldfile
          endif
          p = index( outfieldfile(1), '.', back=.true.)
          outfext =  outfieldfile(1)(p+1:len_trim( outfieldfile(1)))
          ! There is on and field extension are 'ip' or 'dex'
          if ((id_field_ext(outfext) == id_field_ext('ip') .or. &
             & id_field_ext(outfext) == id_field_ext('dex')) .and. is_arg('-on')) then
            str = get_post_arg('-on')
            p = index(str, '[')
            if (p == 0) then !a single field name
              call set(outfieldname, str, 1, fit=.true.)
            else !several subdomain refs. enclosed in [] and separated by ,
              q = index(str, ']', back=.true.)
              call alloc(outfieldname, word_count(str(p+1:q-1),','))
              read(str(p+1:q-1),*) outfieldname
            end if
          endif
        endif
      end if
    else
      !infieldfile is mesh external, outfieldfile is mesh internal
      if (is_arg('-if')) then
        !there is -if
        str = get_post_arg('-if')
        p = index(str, '[')
        if (p == 0) then !a single field name
          call set(infieldfile, str, 1, fit=.true.)
        else !several subdomain refs. enclosed in [] and separated by ,
          q = index(str, ']', back=.true.)
          call alloc(infieldfile, word_count(str(p+1:q-1),','))
          read(str(p+1:q-1),*) infieldfile
        end if
        p = index( infieldfile(1), '.', back=.true.)
        infext =  infieldfile(1)(p+1:len_trim( infieldfile(1)))
        ! There is in and field extension is 'ip'
        if (id_field_ext(infext) == id_field_ext('ip') .and. is_arg('-in')) then
          str = get_post_arg('-in')
          p = index(str, '[')
          if (p == 0) then !a single field name
            call set(infieldname, str, 1, fit=.true.)
          else !several subdomain refs. enclosed in [] and separated by ,
            q = index(str, ']', back=.true.)
            call alloc(infieldname, word_count(str(p+1:q-1),','))
            read(str(p+1:q-1),*) infieldname
          end if
        endif
        ! There is on
        if (is_arg('-on')) then
          str = get_post_arg('-on')
          p = index(str, '[')
          if (p == 0) then !a single field name
            call set(outfieldname, str, 1, fit=.true.)
          else !several subdomain refs. enclosed in [] and separated by ,
            q = index(str, ']', back=.true.)
            call alloc(outfieldname, word_count(str(p+1:q-1),','))
            read(str(p+1:q-1),*) outfieldname
          end if
        endif
      else
        there_is_field = .false.
      end if
    end if
  elseif (FLDB(id_mesh_ext(outext))%is_field_outside) then
    !infieldfile is mesh internal, outfieldfile is mesh external
    if (is_arg('-of')) then
      !there is -of
        str = get_post_arg('-of')
        p = index(str, '[')
        if (p == 0) then !a single field name
          call set(outfieldfile, str, 1, fit=.true.)
        else !several subdomain refs. enclosed in [] and separated by ,
          q = index(str, ']', back=.true.)
          call alloc(outfieldfile, word_count(str(p+1:q-1),','))
          read(str(p+1:q-1),*) outfieldfile
        end if
      p = index( outfieldfile(1), '.', back=.true.)
      outfext =  outfieldfile(1)(p+1:len_trim( outfieldfile(1)))
      ! There is in and mesh extension is not 'pf3'
       if (id_mesh_ext(inext) /= id_mesh_ext('pf3') .and. is_arg('-in')) then
         str = get_post_arg('-in')
         p = index(str, '[')
         if (p == 0) then !a single field name
           call set(infieldname, str, 1, fit=.true.)
         else !several subdomain refs. enclosed in [] and separated by ,
           q = index(str, ']', back=.true.)
           call alloc(infieldname, word_count(str(p+1:q-1),','))
           read(str(p+1:q-1),*) infieldname
         end if
       endif
      ! There is on and field extension is not 'mff' and 'muf'
       if ((id_field_ext(inext) /= id_field_ext('mff') .and. &
          & id_field_ext(inext) /= id_field_ext('muf')) .and. is_arg('-on')) then
         str = get_post_arg('-on')
         p = index(str, '[')
         if (p == 0) then !a single field name
           call set(outfieldname, str, 1, fit=.true.)
         else !several subdomain refs. enclosed in [] and separated by ,
           q = index(str, ']', back=.true.)
           call alloc(outfieldname, word_count(str(p+1:q-1),','))
           read(str(p+1:q-1),*) outfieldname
         end if
       endif
    end if
  else
    !infieldfile and outfieldfile are both mesh internal
    ! There is on
    if (is_arg('-in')) then
      str = get_post_arg('-in')
      p = index(str, '[')
      if (p == 0) then !a single field name
        call set(infieldname, str, 1, fit=.true.)
      else !several subdomain refs. enclosed in [] and separated by ,
        q = index(str, ']', back=.true.)
        call alloc(infieldname, word_count(str(p+1:q-1),','))
        read(str(p+1:q-1),*) infieldname
      end if
    endif
    ! There is on
    if (is_arg('-on')) then
      str = get_post_arg('-on')
      p = index(str, '[')
      if (p == 0) then !a single field name
        call set(outfieldname, str, 1, fit=.true.)
      else !several subdomain refs. enclosed in [] and separated by ,
        q = index(str, ']', back=.true.)
        call alloc(outfieldname, word_count(str(p+1:q-1),','))
        read(str(p+1:q-1),*) outfieldname
      end if
    endif
  end if
endif

! Sets the field padding value
if (is_arg('-pad')) then
  padval = dble(get_post_arg('-pad'))
else
  padval = 0._real64
endif

!read mesh
is_pmh = .false.
select case (trim(lcase(adjustlt(inext))))
case('mfm')
  print '(a)', 'Loading MFM mesh file...'
  call load_mfm(infile, get_unit(), nel, nnod, nver, dim, lnn, lnv, lne, lnf, nn, mm, nrc, nra, nrv, z, nsd)
  print '(a)', 'Done!'
case('mum')
  print '(a)', 'Loading MUM mesh file...'
  call load_mum(infile, get_unit(), nel, nnod, nver, dim, lnn, lnv, lne, lnf, nn, mm, nrc, nra, nrv, z, nsd)
  print '(a)', 'Done!'
case('msh')
  if (is_arg('-ff')) then !FreeFem++
    print '(a)', 'Loading FreFem++ (.msh) mesh file...'
    call load_freefem_msh(infile, get_unit(), pmh); is_pmh = .true.
  elseif (is_arg('-gm')) then !Gmsh
    print '(a)', 'Loading Gmsh (.msh) mesh file...'
    call load_gmsh(infile, get_unit(), pmh); is_pmh = .true.
  else !ANSYS
    print '(a)', 'Loading ANSYS mesh file...'
    call load_msh(infile, pmh); is_pmh = .true.
  end if
  print '(a)', 'Done!'
case('unv')
  print '(a)', 'Loading UNV mesh file...'
  call load_unv(infile, pmh, padval, infieldname, is_arg('-ca')); is_pmh = .true.
  print '(a)', 'Done!'
case('bdf')
  print '(a)', 'Loading MD Nastran input file...'
  call load_patran(infile, get_unit(), nel, nnod, nver, dim, lnn, lnv, lne, lnf, nn, mm, nrc, nra, nrv, z, nsd)
  print '(a)', 'Done!'
case('mphtxt')
  print '(a)', 'Loading COMSOL mesh file...'
  call load_mphtxt(infile, pmh); is_pmh = .true.
  print '(a)', 'Done!'
case('pf3')
  print '(a)', 'Loading FLUX mesh file...'
  call load_pf3(infile, pmh); is_pmh = .true.
case('vtu')
  print '(a)', 'Loading VTU mesh file...'
  call load_vtu( infile, pmh, infieldname); is_pmh = .true.
  print '(a)', 'Done!'
case('pvd')
  print '(a)', 'Loading PVD file...'
  call load_pvd( infile, pmh, infieldname); is_pmh = .true.
  print '(a)', 'Done!'
case('mesh')
  print '(a)', 'Loading FreFem++ (Tetrahedral Lagrange P1) MESH file...'
  call load_freefem_mesh(infile, get_unit(), pmh); is_pmh = .true.
  print '(a)', 'Done!'
case default
  call error('(module_feconv/fe_conv) input file extension not implemented: '//trim(adjustlt(inext)))
end select

! Read field files
if(there_is_field .and. is_arg('-if')) then
  if (.not.is_pmh) call mfm2pmh(nel, nnod, nver, dim, lnn, lnv, lne, lnf, nn, mm, nrc, nra, nrv, z, nsd, pmh)
  is_pmh = .true.

  select case (trim(lcase(adjustlt(infext))))
    case('mff')
      call load_mff(pmh, infieldfile, infieldname)
    case('muf')
      call load_muf(pmh, infieldfile, infieldname)
    case('dex')
      call load_dex(pmh, infieldfile, infieldname)
    case('ip')
      call load_ip(pmh, infieldfile, infieldname, outfieldname)
  end select

endif

! Show PMH info in screen
if(is_arg('-l')) then
  if (.not.is_pmh) call mfm2pmh(nel, nnod, nver, dim, lnn, lnv, lne, lnf, nn, mm, nrc, nra, nrv, z, nsd, pmh)
  is_pmh = .true.
  call save_pmh2(infile, pmh, with_values=.false.)
  stop
endif


! Remove a component of the space dimension
if (is_arg('-rc')) then
 comp = int(get_post_arg('-rc'))
 if (.not. is_pmh) then
   call mfm2pmh(nel, nnod, nver, dim, lnn, lnv, lne, lnf, nn, mm, nrc, nra, nrv, z, nsd, pmh)
   is_pmh=.true.
 endif

 call remove_coordinate(pmh, comp)
endif


!extract (only for Lagrange P1 meshes)
if (is_arg('-es')) then
  str = get_post_arg('-es')
  print '(/a)', 'Extracting subdomain(s) '//trim(str)//'...'
  p = index(str, '[')
  if (p == 0) then !a single subdomain ref.
    call set(nsd0, int(str), 1, fit=.true.)
  else !several subdomain refs. enclosed in [] and separated by ,
    q = index(str, ']', back=.true.)
    call alloc(nsd0, word_count(str(p+1:q-1),','))
    read(str(p+1:q-1),*) nsd0
  end if
  if (is_pmh) call pmh2mfm(pmh, nel, nnod, nver, dim, lnn, lnv, lne, lnf, nn, mm, nrc, nra, nrv, z, nsd); is_pmh = .false.
  if (nver /= nnod) call error('(module_feconv/fe_conv) extraction is only available for Lagrange P1 meshes.')
  call extract_mesh(nver, mm, z, nsd, nsd0, submm, subz, globv, globel)
  call extract_ref(nrv, nra, nrc, nsd, subnrv, subnra, subnrc, subnsd, globel)
  nel  = size(submm, 2)
  nver = size(subz,  2)
  nnod = nver
  call move_alloc(from=submm,  to=mm)
  call move_alloc(from=subnrv, to=nrv)
  call move_alloc(from=subnra, to=nra)
  call move_alloc(from=subnrc, to=nrc)
  call move_alloc(from=subz,   to=z)
  call move_alloc(from=subnsd, to=nsd)
  print '(a)', 'Done!'
end if

!transform
if (is_arg('-l1')) then
  print '(/a)', 'Converting mesh into Lagrange P1 mesh...'
  if (.not. is_pmh) then
    call mfm2pmh(nel, nnod, nver, dim, lnn, lnv, lne, lnf, nn, mm, nrc, nra, nrv, z, nsd, pmh)
    is_pmh = .true.
  end if
  call to_l1(pmh)
  print '(a)', 'Done!'
elseif (is_arg('-l2')) then
  print '(/a)', 'Converting Lagrange P1 mesh into Lagrange P2 mesh...'
  if (is_pmh) then
    call pmh2mfm(pmh, nel, nnod, nver, dim, lnn, lnv, lne, lnf, nn, mm, nrc, nra, nrv, z, nsd)
    is_pmh = .false.
  end if
  call lagr2l2(nel, nnod, nver, dim, lnn, lnv, lne, lnf, nn, mm)
  print '(a)', 'Done!'
elseif (is_arg('-rt')) then
  print '(/a)', 'Converting Lagrange mesh into Raviart-Thomas (face) mesh...'
  if (is_pmh) then
    call pmh2mfm(pmh, nel, nnod, nver, dim, lnn, lnv, lne, lnf, nn, mm, nrc, nra, nrv, z, nsd)
    is_pmh = .false.
  end if
  call lagr2rt(nel, nnod, nver, dim, lnn, lnv, lne, lnf, nn, mm)
  print '(a)', 'Done!'
elseif (is_arg('-nd')) then
  print '(/a)', 'Converting Lagrange mesh into Whitney (edge) mesh...'
  if (is_pmh) then
    call pmh2mfm(pmh, nel, nnod, nver, dim, lnn, lnv, lne, lnf, nn, mm, nrc, nra, nrv, z, nsd)
    is_pmh = .false.
  end if
  call lagr2nd(nel, nnod, nver, dim, lnn, lnv, lne, lnf, nn, mm)
  print '(a)', 'Done!'
end if

!bandwidth optimization
if (is_arg('-cm')) then
  if (is_pmh) call pmh2mfm(pmh, nel, nnod, nver, dim, lnn, lnv, lne, lnf, nn, mm, nrc, nra, nrv, z, nsd)
  call cuthill_mckee(nel, nnod, nver, dim, lnn, lnv, lne, lnf, nn, mm, z); is_pmh = .false.
end if

if (is_arg('-cn')) then
  if (.not. is_pmh) call mfm2pmh(nel, nnod, nver, dim, lnn, lnv, lne, lnf, nn, mm, nrc, nra, nrv, z, nsd, pmh)
  call cell2node(pmh)
end if

if(present(mempmh)) then
  if (.not. is_pmh) call mfm2pmh(nel, nnod, nver, dim, lnn, lnv, lne, lnf, nn, mm, nrc, nra, nrv, z, nsd, pmh)
  mempmh = pmh
else
  !save mesh
  select case (trim(adjustlt(outext)))
  case('mfm')
    print '(/a)', 'Saving MFM mesh file...'
    if (is_pmh) call pmh2mfm(pmh, nel, nnod, nver, dim, lnn, lnv, lne, lnf, nn, mm, nrc, nra, nrv, z, nsd)
    call save_mfm(outfile, get_unit(), nel, nnod, nver, dim, lnn, lnv, lne, lnf, nn, mm, nrc, nra, nrv, z, nsd)
    print '(a)', 'Done!'
  case('mum')
    print '(/a)', 'Saving MUM mesh file...'
    if (is_pmh) call pmh2mfm(pmh, nel, nnod, nver, dim, lnn, lnv, lne, lnf, nn, mm, nrc, nra, nrv, z, nsd)
    call save_mum(outfile, get_unit(), nel, nnod, nver, dim, lnn, lnv, lne, lnf, nn, mm, nrc, nra, nrv, z, nsd)
    print '(a)', 'Done!'
  case('vtu')
    print '(/a)', 'Saving VTU mesh file...'
    if (is_pmh) then
      call save_vtu(outfile, pmh,infieldname, outfieldname, padval)
    else
      call save_vtu(outfile, nel, nnod, nver, dim, lnn, lnv, lne, lnf, nn, mm, nrc, nra, nrv, z, nsd)
    endif
    print '(a)', 'Done!'
  !case('vtu')
  !  print '(/a)', 'Saving VTU mesh file...'
  !  if (.not. is_pmh) call mfm2pmh(nel, nnod, nver, dim, lnn, lnv, lne, lnf, nn, mm, nrc, nra, nrv, z, nsd, pmh)
  !  call save_vtu2(outfile, pmh)
  !  print '(a)', 'Done!'
  case('pvd')
    print '(/a)', 'Saving PVD file...'
    if (.not. is_pmh) call mfm2pmh(nel, nnod, nver, dim, lnn, lnv, lne, lnf, nn, mm, nrc, nra, nrv, z, nsd, pmh)
    call save_pvd(outfile, pmh,infieldname, outfieldname, padval)
    print '(a)', 'Done!'
  case('mphtxt')
    print '(/a)', 'Saving COMSOL mesh file...'
    if (.not. is_pmh) call mfm2pmh(nel, nnod, nver, dim, lnn, lnv, lne, lnf, nn, mm, nrc, nra, nrv, z, nsd, pmh)
    call save_mphtxt(outfile, pmh)
    print '(a)', 'Done!'
  case('unv')
    print '(/a)', 'Saving I-DEAS UNV mesh file...'
    if (.not. is_pmh) call mfm2pmh(nel, nnod, nver, dim, lnn, lnv, lne, lnf, nn, mm, nrc, nra, nrv, z, nsd, pmh)
    call save_unv(outfile, get_unit(), pmh, infieldname, outfieldname, is_arg('-ca'))
    print '(a)', 'Done!'
  case('pf3')
    print '(/a)', 'Saving FLUX mesh file...'
    if (.not. is_pmh) call mfm2pmh(nel, nnod, nver, dim, lnn, lnv, lne, lnf, nn, mm, nrc, nra, nrv, z, nsd, pmh)
    call save_pf3(outfile, pmh, infieldname, outfieldname, outpath)
    print '(a)', 'Done!'
  case('msh')
    if (is_arg('-ff')) then !FreeFem++
      print '(/a)', 'Saving FreFem++ mesh file...'
      if (.not. is_pmh) call mfm2pmh(nel, nnod, nver, dim, lnn, lnv, lne, lnf, nn, mm, nrc, nra, nrv, z, nsd, pmh)
      call save_freefem_msh(outfile, get_unit(), pmh)
    elseif (is_arg('-gm')) then !Gmsh
      print '(/a)', 'Saving Gmsh mesh file...'
      if (.not. is_pmh) call mfm2pmh(nel, nnod, nver, dim, lnn, lnv, lne, lnf, nn, mm, nrc, nra, nrv, z, nsd, pmh)
      call save_gmsh(outfile, get_unit(), pmh)
    else !ANSYS
      print '(/a)', 'Saving ANSYS mesh file...'
      if (.not. is_pmh) call mfm2pmh(nel, nnod, nver, dim, lnn, lnv, lne, lnf, nn, mm, nrc, nra, nrv, z, nsd, pmh)
      call save_msh(outfile, pmh)
    end if
    print '(a)', 'Done!'
  case('mesh')
    print '(/a)', 'Saving FreFem++ mesh file...'
    if (.not. is_pmh) call mfm2pmh(nel, nnod, nver, dim, lnn, lnv, lne, lnf, nn, mm, nrc, nra, nrv, z, nsd, pmh)
    call save_freefem_mesh(outfile, get_unit(), pmh)
    print '(a)', 'Done!'
  case('pmh')
    print '(/a)', 'Saving PMH mesh file...'
    if (.not. is_pmh) call mfm2pmh(nel, nnod, nver, dim, lnn, lnv, lne, lnf, nn, mm, nrc, nra, nrv, z, nsd, pmh)
    call save_pmh(outfile, pmh)
    print '(a)', 'Done!'
  end select !case default, already checked before reading infile
  !save fields
  if(is_pmh .and. there_is_field .and. is_arg('-of')) then
    select case (trim(lcase(adjustlt(outfext))))
      case('mff')
        call save_mff(pmh, outfieldfile, outpath)
      case('muf')
        call save_muf(pmh, outfieldfile, outpath)
      case('dex')
        call save_dex(pmh, infieldname, outfieldname, outfieldfile)
      case('ip')
        call save_ip(pmh, outfieldfile, infieldname, outfieldname)
      case default
        call info('Field file extension "'//trim(lcase(adjustlt(outfext)))//'" not supported!')
    end select
  endif
endif 
end subroutine

end module
