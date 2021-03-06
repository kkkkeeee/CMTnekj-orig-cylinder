C> @file step.f time stepping and mesh spacing routines
      subroutine setdtcmt
!--------------------------------------------------------------
! JH072914 now summed instead of maximized for compressible flow
! JH082015 why was I doing that again?
!     someday compute new timestep based on CFL-condition. follow
!     setdtc in nek/subs1.f very carefully.
! JH091616 now with diffusion number for naively explicit visc
! JH091616 consider migrating to compute_cfl
! JH120116 Why aren't we including total again?
!--------------------------------------------------------------
      include 'SIZE'
      include 'GEOM'
      include 'MVGEOM'
      include 'MASS'
      include 'INPUT'
      include 'SOLN'
      include 'TSTEP'
      include 'CMTDATA'

!--------------------------------------------------------------
! YOU REALLY PROBABLY WANT YOUR OWN SCRATCH SPACE FOR THIS
      common /scrsf/ u1(lx1,ly1,lz1,lelt) ! mind if I borrow this?
     $ ,             v(lx1,ly1,lz1,lelt) ! as long as the mesh
     $ ,             w(lx1,ly1,lz1,lelt) ! doesn't move
! YOU REALLY PROBABLY WANT YOUR OWN SCRATCH SPACE FOR THAT
!--------------------------------------------------------------

      common /udxmax/ umax
      REAL VCOUR
      SAVE VCOUR
      REAL mdr
      SAVE mdr

      NTOT   = NX1*NY1*NZ1*NELV
      NTOTL  = LX1*LY1*LZ1*lelt
      NTOTD  = NTOTL*NDIM
      COLD   = COURNO
      CMAX   = 1.2*CTARG
      CMIN   = 0.8*CTARG
      do i=1,ntot
         u1(i,1,1,1) = abs(vx(i,1,1,1))+csound(i,1,1,1)
         v (i,1,1,1) = abs(vy(i,1,1,1))+csound(i,1,1,1)
         w (i,1,1,1) = abs(vz(i,1,1,1))+csound(i,1,1,1)
      enddo
      CALL CUMAX (u1,v,w,UMAX)
      COURNO = DT*UMAX
      VOLD   = VCOUR
      VCOUR  = UMAX

! diffusion number based on viscosity.

!     call mindr(mdr,diffno2)
      call glinvcol2max(diffno1,vdiff(1,1,1,1,imu), gridh,ntot,dt)
      call glinvcol2max(diffno2,vdiff(1,1,1,1,iknd),gridh,ntot,dt)
      call glinvcol2max(diffno3,vdiff(1,1,1,1,inus),gridh,ntot,dt)
!     diffno=max(diffno1,diffno2,diffno3)
      if (nio.eq.0) WRITE(6,100)ISTEP,TIME,DT,COURNO,diffno1,diffno2,
     >   diffno3
 100  FORMAT('CMT ',I7,', t=',1pE14.7,', DT=',1pE14.7
     $,', C=',1pE12.5,', Dmu,knd,art=',3(1pE11.4))
!     Zero DT
!
!     IF (DT .EQ. 0.0) THEN
!
!        IF (UMAX .NE. 0.0) THEN
!           DT = CTARG/UMAX
!           VCOUR = UMAX
      return
      end

      subroutine mindr(mdr,diffno)
c
c     Find minimum distance between grid points
c     and multiply it by viscosity to get diffusion number
c     Probably need to do this for energy equation too...
! JH091616 migrate to getdr 3d ASAP. Again, follow compute_cfl
      include 'SIZE'
      include 'TOTAL'
      include 'CMTDATA'

      real    mdr,dr1
      real    x0,x1,x2,x3,x4,y0,y1,y2,y3,y4
      integer e
c
      mdr=1.e5
      if(if3d) then
        write(6,*)'TODO:: mindr for 3D. getdr'
        call exitt
      else
        diffno=0.0
        do e=1,nelt
          do iy=2,ny1-1
          do ix=2,nx1-1
            dtmp=1.0e5
            x0 = xm1(ix  ,iy  ,1,e)
            x1 = xm1(ix  ,iy-1,1,e)
            x2 = xm1(ix+1,iy  ,1,e)
            x3 = xm1(ix  ,iy+1,1,e)
            x4 = xm1(ix-1,iy  ,1,e)
            y0 = ym1(ix  ,iy  ,1,e)
            y1 = ym1(ix  ,iy-1,1,e)
            y2 = ym1(ix+1,iy  ,1,e)
            y3 = ym1(ix  ,iy+1,1,e)
            y4 = ym1(ix-1,iy  ,1,e)
            dr1 = dist2(x0,y0,x1,y1)
            if(dr1.lt.mdr) mdr=dr1
            if(dr1.lt.dtmp) dtmp=dr1
            dr1 = dist2(x0,y0,x2,y2)
            if(dr1.lt.mdr) mdr=dr1
            if(dr1.lt.dtmp) dtmp=dr1
            dr1 = dist2(x0,y0,x3,y3)
            if(dr1.lt.mdr) mdr=dr1
            if(dr1.lt.dtmp) dtmp=dr1
            dr1 = dist2(x0,y0,x4,y4)
            if(dr1.lt.mdr) mdr=dr1
            if(dr1.lt.dtmp) dtmp=dr1
            diffno=max(diffno,dt*vdiff(ix,iy,1,e,imu)/dtmp/dtmp)
          enddo
          enddo
        enddo
      endif
      diffno=glmax(diffno,1)
      mdr = glmin(mdr,1)
      if(mdr.ge.1.e5) write(6,*) 'wrong mdr'

      return
      end

      real function dist2(x1,y1,x2,y2)
      real x1,y1,x2,y2,dx,dy
c
      dx = x1-x2
      dy = y1-y2
      dist2 = sqrt(dx*dx+dy*dy)
c
      return
      end

!-----------------------------------------------------------------------

      subroutine compute_grid_h(h,x,y,z)
! Richard Pasquetti SEM "grid spacing h." good parallelogram/piped stuff
      include 'SIZE'
      include 'INPUT'
      include 'GEOM'
      real a(3), b(3), c(3), d(3)
      real h(nx1,ny1,nz1,nelt) ! intent(out)
      real x(nx1,ny1,nz1,nelt) ! intent(in)
      real y(nx1,ny1,nz1,nelt) ! intent(in)
      real z(nx1,ny1,nz1,nelt) ! intent(in)
      integer e
      integer icalld
      data icalld /0/
      save icalld
      
      if (icalld .eq. 1) then
         return
      else
         icalld=1
      endif

      do e=1,nelt
         do iz=1,nz1
            if (if3d) then
               km1=iz-1
               kp1=iz+1
               izm=km1
               if (km1 .lt. 1) izm=iz
               izp=kp1
               if (kp1 .gt. nz1) izp=iz
            else
               izm=iz
               izp=iz
            endif
            do iy=1,ny1
               jm1=iy-1
               jp1=iy+1
               iym=jm1
               if (jm1 .lt. 1) iym=iy
               iyp=jp1
               if (jp1 .gt. ny1) iyp=iy
               do ix=1,nx1
                  im1=ix-1
                  ip1=ix+1
                  ixm=im1
                  if (im1 .lt. 1) ixm=ix
                  ixp=ip1
                  if (ip1 .gt. nx1) ixp=ix
                  x1 = x(ixm,iy ,iz ,e)
                  x2 = x(ixp,iy ,iz ,e)
                  x3 = x(ix ,iym,iz ,e)
                  x4 = x(ix ,iyp,iz ,e)
                  x5 = x(ix ,iy ,izm,e)
                  x6 = x(ix ,iy ,izp,e)
                  y1 = y(ixm,iy ,iz ,e)
                  y2 = y(ixp,iy ,iz ,e)
                  y3 = y(ix ,iym,iz ,e)
                  y4 = y(ix ,iyp,iz ,e)
                  y5 = y(ix ,iy ,izm,e)
                  y6 = y(ix ,iy ,izp,e)
                  z1 = z(ixm,iy ,iz ,e)
                  z2 = z(ixp,iy ,iz ,e)
                  z3 = z(ix ,iym,iz ,e)
                  z4 = z(ix ,iyp,iz ,e)
                  z5 = z(ix ,iy ,izm,e)
                  z6 = z(ix ,iy ,izp,e)
                  a(1)=x2-x1
                  a(2)=y2-y1
                  a(3)=z2-z1
                  b(1)=x4-x3
                  b(2)=y4-y3
                  b(3)=z4-z3
                  c(1)=x6-x5
                  c(2)=y6-y5
                  c(3)=z6-z5
                  if (if3d) then
                     fact=0.125 ! h doesn't reach into corners of neighboring elements
                     if (ixp.eq.ix.or.ixm.eq.ix) fact=2.0*fact
                     if (iym.eq.iy.or.iyp.eq.iy) fact=2.0*fact
                     if (izm.eq.iz.or.izp.eq.iz) fact=2.0*fact
                     call cross(d,a,b)
                     h(ix,iy,iz,e)=fact*dot(c,d,3)
                     h(ix,iy,iz,e)=abs(h(ix,iy,iz,e))**(1.0/3.0)
                  else
                     fact=0.25
                     if (ixp.eq.ix.or.ixm.eq.ix) fact=2.0*fact
                     if (iym.eq.iy.or.iyp.eq.iy) fact=2.0*fact
                     h(ix,iy,iz,e)=sqrt(fact*abs(a(1)*b(2)-a(2)*b(1)))
                  endif
               enddo
            enddo
         enddo
      enddo

      return
      end

!-----------------------------------------------------------------------

      subroutine glinvcol2max(col2m,a,b,n,s)
      real col2m
      real s
      real a(*),b(*)
      tmp=0.0
      do i=1,n
         tmp=max(tmp,abs(s*a(i)/b(i)/b(i)))
      enddo
      col2m=glamax(tmp,1)
      return
      end

!-----------------------------------------------------------------------

      subroutine compute_mesh_h(h,x,y,z)
! Zingan's DGFEM formula: h=minimum distance between vertices divided by
!                         polynomial order
      include 'SIZE'
      include 'INPUT'
      real h(nelt)             ! intent(out)
      real x(nx1,ny1,nz1,nelt) ! intent(in)
      real y(nx1,ny1,nz1,nelt) ! intent(in)
      real z(nx1,ny1,nz1,nelt) ! intent(in)
      real xcrn(8),ycrn(8),zcrn(8)
      integer e
      integer icalld
      data icalld /0/
      save icalld
      
      if (icalld .eq. 1) then
         return
      else
         icalld=1
      endif

      ncrn=2**ndim
      rp=1.0/((nx1-1))

      do e=1,nelt
         call rzero(zcrn,8)
         k1=1
         k2=nz1
         j1=1
         j2=ny1
         i1=1
         i2=nx1
         xcrn(1) = x(i1,j1,k1,e)
         xcrn(2) = x(i2,j1,k1,e)
         xcrn(3) = x(i1,j2,k1,e)
         xcrn(4) = x(i2,j2,k1,e)
         ycrn(1) = y(i1,j1,k1,e)
         ycrn(2) = y(i2,j1,k1,e)
         ycrn(3) = y(i1,j2,k1,e)
         ycrn(4) = y(i2,j2,k1,e)
         if (if3d) then
            xcrn(5) = x(i1,j1,k2,e)
            xcrn(6) = x(i2,j1,k2,e)
            xcrn(7) = x(i1,j2,k2,e)
            xcrn(8) = x(i2,j2,k2,e)
            ycrn(5) = y(i1,j1,k2,e)
            ycrn(6) = y(i2,j1,k2,e)
            ycrn(7) = y(i1,j2,k2,e)
            ycrn(8) = y(i2,j2,k2,e)
            zcrn(1) = z(i1,j1,k1,e)
            zcrn(2) = z(i2,j1,k1,e)
            zcrn(3) = z(i1,j2,k1,e)
            zcrn(4) = z(i2,j2,k1,e)
            zcrn(5) = z(i1,j1,k2,e)
            zcrn(6) = z(i2,j1,k2,e)
            zcrn(7) = z(i1,j2,k2,e)
            zcrn(8) = z(i2,j2,k2,e)
         endif
         dist=1.0e36
         do ic1=1,ncrn
            do ic2=1,ncrn
               if (ic2 .ne. ic1) then
                  dtmp=(xcrn(ic2)-xcrn(ic1))**2+
     >                 (ycrn(ic2)-ycrn(ic1))**2+
     >                 (zcrn(ic2)-zcrn(ic1))**2
                  dist=min(dist,sqrt(dtmp))
               endif
            enddo
         enddo
         h(e)=dist*rp
      enddo

      return
      end
