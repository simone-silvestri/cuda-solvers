
/**
 * Copyright 1993-2012 NVIDIA Corporation.  All rights reserved.
 *
 * Please refer to the NVIDIA end user license agreement (EULA) associated
 * with this source code for terms and conditions that govern your use of
 * this software. Any use, reproduction, disclosure, or distribution of
 * this software and related documentation outside the terms of the EULA
 * is strictly prohibited.
 */

#include "globals.h"
#include "cuda_functions.h"
#include "cuda_math.h"


/*
 *  The L-versions of the RHS have to be ran with
 *  - the L-version of the derivatives
 *  i.e.: derDev1xL instead of derDev1x
 *  - the L-version of the grid
 *  i.e.: h_gridL[0] instead of h_grid[0]
 */

__device__ myprec *d_workY1;
__device__ myprec *d_workY2;

__device__ myprec *d_workZ1;
__device__ myprec *d_workZ2;


/* The whole RHS in the X direction is calculated in RHSDeviceSharedFlxX thanks to the beneficial memory layout that allows to use small pencils */
/* For the Y and Z direction, fluxes require a small pencil discretization while the rest of the RHS can be calculated on large pencils which speed
 * up significantly the computation. Therefore 5 streams are used
 * stream 0 -> complete X RHS (in RHSDeviceSharedFlxX) (small pencil grid)
 * stream 1 -> viscous terms and pressure terms in Y (in RHSDeviceFullYL) (large pencil grid)
 * stream 2 -> viscous terms and pressure terms in Z (in RHSDeviceFullZL) (large pencil grid)
 * stream 3 -> advective fluxes in Y direction (in FLXDeviceY) (small pencil transposed grid)
 * stream 4 -> advective fluxes in Z direction (in FLXDeviceZ) (small pencil transposed grid)*/


__global__ void RHSDeviceSharedFlxX(myprec *rX, myprec *uX, myprec *vX, myprec *wX, myprec *eX,
		myprec *r,  myprec *u,  myprec *v,  myprec *w,  myprec *h ,
		myprec *t,  myprec *p,  myprec *mu, myprec *lam,
		myprec *sij[9], myprec *dil) {

	Indices id(threadIdx.x,threadIdx.y,blockIdx.x,blockIdx.y,blockDim.x,blockDim.y);
	id.mkidX();

	int si = id.i + stencilSize;       // local i for shared memory access + halo offset
	int sj = id.tiy;                   // local j for shared memory access

	myprec rXtmp=0;
	myprec uXtmp=0;
	myprec vXtmp=0;
	myprec wXtmp=0;
	myprec eXtmp=0;

	myprec wrk1=0;
	myprec wrk2=0;

	__shared__ myprec s_r[sPencils][mx+stencilSize*2];
	__shared__ myprec s_u[sPencils][mx+stencilSize*2];
	__shared__ myprec s_v[sPencils][mx+stencilSize*2];
	__shared__ myprec s_w[sPencils][mx+stencilSize*2];
	__shared__ myprec s_h[sPencils][mx+stencilSize*2];
	__shared__ myprec s_t[sPencils][mx+stencilSize*2];
	__shared__ myprec s_p[sPencils][mx+stencilSize*2];
	__shared__ myprec s_m[sPencils][mx+stencilSize*2];
	__shared__ myprec s_l[sPencils][mx+stencilSize*2];
	__shared__ myprec s_wrk[sPencils][mx+stencilSize*2];

	s_r[sj][si] = r[id.g];
	s_u[sj][si] = u[id.g];
	s_v[sj][si] = v[id.g];
	s_w[sj][si] = w[id.g];
	s_h[sj][si] = h[id.g];
	s_t[sj][si] = t[id.g];
	s_p[sj][si] = p[id.g];
	s_m[sj][si] = mu[id.g];
	s_l[sj][si] = lam[id.g];
	__syncthreads();

	// fill in periodic images in shared memory array
	if (id.i < stencilSize) {
		s_r[sj][si-stencilSize]  = s_r[sj][si+mx-stencilSize];
		s_r[sj][si+mx]           = s_r[sj][si];
		s_u[sj][si-stencilSize]  = s_u[sj][si+mx-stencilSize];
		s_u[sj][si+mx]           = s_u[sj][si];
		s_v[sj][si-stencilSize]  = s_v[sj][si+mx-stencilSize];
		s_v[sj][si+mx]           = s_v[sj][si];
		s_w[sj][si-stencilSize]  = s_w[sj][si+mx-stencilSize];
		s_w[sj][si+mx]           = s_w[sj][si];
		s_h[sj][si-stencilSize]  = s_h[sj][si+mx-stencilSize];
		s_h[sj][si+mx]           = s_h[sj][si];
		s_t[sj][si-stencilSize]  = s_t[sj][si+mx-stencilSize];
		s_t[sj][si+mx]           = s_t[sj][si];
		s_p[sj][si-stencilSize]  = s_p[sj][si+mx-stencilSize];
		s_p[sj][si+mx]           = s_p[sj][si];
		s_m[sj][si-stencilSize]  = s_m[sj][si+mx-stencilSize];
		s_m[sj][si+mx]           = s_m[sj][si];
		s_l[sj][si-stencilSize]  = s_l[sj][si+mx-stencilSize];
		s_l[sj][si+mx]           = s_l[sj][si];
	}

	__syncthreads();

	// viscous fluxes derivative
	derDevSharedV2x(&wrk1,s_u[sj],si);
	uXtmp = wrk1*s_m[sj][si];
	derDevSharedV2x(&wrk1,s_v[sj],si);
	vXtmp = wrk1*s_m[sj][si];
	derDevSharedV2x(&wrk1,s_w[sj],si);
	wXtmp = wrk1*s_m[sj][si];
	derDevSharedV2x(&wrk1,s_t[sj],si);
	eXtmp = wrk1*s_l[sj][si];
	__syncthreads();
	derDevSharedV1x(&wrk2,s_l[sj],si); //wrk2 = d (lam) dx
	derDevSharedV1x(&wrk1,s_t[sj],si); //wrk1 = d (t) dx
	eXtmp = eXtmp + wrk1*wrk2;

	//Adding here the terms d (mu) dx * sxj; (lambda in case of h in rhse);

	derDevSharedV1x(&wrk2,s_m[sj],si); //wrk2 = d (mu) dx
	uXtmp = uXtmp + wrk2*sij[0][id.g];
	vXtmp = vXtmp + wrk2*sij[1][id.g];
	wXtmp = wXtmp + wrk2*sij[2][id.g];

	// split advection terms

	//Adding here the terms - d (ru phi) dx;

	fluxQuadSharedx(&wrk1,s_r[sj],s_u[sj],si);
	rXtmp = wrk1;
	__syncthreads();
	fluxCubeSharedx(&wrk1,s_r[sj],s_u[sj],s_u[sj],si);
	uXtmp = uXtmp + wrk1;
	__syncthreads();
	fluxCubeSharedx(&wrk1,s_r[sj],s_u[sj],s_v[sj],si);
	vXtmp = vXtmp + wrk1;
	__syncthreads();
	fluxCubeSharedx(&wrk1,s_r[sj],s_u[sj],s_w[sj],si);
	wXtmp = wXtmp + wrk1;
	__syncthreads();
	fluxCubeSharedx(&wrk1,s_r[sj],s_u[sj],s_h[sj],si);
	eXtmp = eXtmp + wrk1;
	__syncthreads();

	// pressure and dilation derivatives
	s_wrk[sj][si] = dil[id.g];
	__syncthreads();
	if (id.i < stencilSize) {
		s_wrk[sj][si-stencilSize]  = s_wrk[sj][si+mx-stencilSize];
		s_wrk[sj][si+mx]           = s_wrk[sj][si];
	}
	__syncthreads();
	derDevSharedV1x(&wrk2,s_wrk[sj],si);
	derDevShared1x(&wrk1,s_p[sj],si);
	uXtmp = uXtmp - wrk1 + s_m[sj][si]*wrk2*1.0/3.0;

	//viscous dissipation
	s_wrk[sj][si] = s_m[sj][si]*(
					s_u[sj][si]*(  sij[0][id.g]  ) +
					s_v[sj][si]*(  sij[1][id.g]  ) +
					s_w[sj][si]*(  sij[2][id.g]  )
					);
	__syncthreads();
	if (id.i < stencilSize) {
		s_wrk[sj][si-stencilSize]  = s_wrk[sj][si+mx-stencilSize];
		s_wrk[sj][si+mx]           = s_wrk[sj][si];
	}
	__syncthreads();
	derDevSharedV1x(&wrk2,s_wrk[sj],si);

	rX[id.g] = rXtmp;
	uX[id.g] = uXtmp;
	vX[id.g] = vXtmp;
	wX[id.g] = wXtmp;
	eX[id.g] = eXtmp + wrk2;
}

__global__ void RHSDeviceSharedFlxY(myprec *rY, myprec *uY, myprec *vY, myprec *wY, myprec *eY,
		myprec *r,  myprec *u,  myprec *v,  myprec *w,  myprec *h ,
		myprec *t,  myprec *p,  myprec *mu, myprec *lam,
		myprec *sij[9], myprec *dil) {

	Indices id(threadIdx.x,threadIdx.y,blockIdx.x,blockIdx.y,blockDim.x,blockDim.y);
	id.mkidYFlx();

	int si = id.j + stencilSize;       // local i for shared memory access + halo offset
	int sj = id.tiy;                   // local j for shared memory access

	myprec rYtmp=0;
	myprec uYtmp=0;
	myprec vYtmp=0;
	myprec wYtmp=0;
	myprec eYtmp=0;

	myprec wrk1=0;
	myprec wrk2=0;

	__shared__ myprec s_r[sPencils][my+stencilSize*2];
	__shared__ myprec s_u[sPencils][my+stencilSize*2];
	__shared__ myprec s_v[sPencils][my+stencilSize*2];
	__shared__ myprec s_w[sPencils][my+stencilSize*2];
	__shared__ myprec s_h[sPencils][my+stencilSize*2];
	__shared__ myprec s_t[sPencils][my+stencilSize*2];
	__shared__ myprec s_p[sPencils][my+stencilSize*2];
	__shared__ myprec s_m[sPencils][my+stencilSize*2];
	__shared__ myprec s_l[sPencils][my+stencilSize*2];
	__shared__ myprec s_wrk[sPencils][my+stencilSize*2];

	s_r[sj][si] = r[id.g];
	s_u[sj][si] = u[id.g];
	s_v[sj][si] = v[id.g];
	s_w[sj][si] = w[id.g];
	s_h[sj][si] = h[id.g];
	s_t[sj][si] = t[id.g];
	s_p[sj][si] = p[id.g];
	s_m[sj][si] = mu[id.g];
	s_l[sj][si] = lam[id.g];
	__syncthreads();

	// fill in periodic images in shared memory array
	if (id.j < stencilSize) {
		s_r[sj][si-stencilSize]  = s_r[sj][si+my-stencilSize];
		s_r[sj][si+my]           = s_r[sj][si];
		s_u[sj][si-stencilSize]  = s_u[sj][si+my-stencilSize];
		s_u[sj][si+my]           = s_u[sj][si];
		s_v[sj][si-stencilSize]  = s_v[sj][si+my-stencilSize];
		s_v[sj][si+my]           = s_v[sj][si];
		s_w[sj][si-stencilSize]  = s_w[sj][si+my-stencilSize];
		s_w[sj][si+my]           = s_w[sj][si];
		s_h[sj][si-stencilSize]  = s_h[sj][si+my-stencilSize];
		s_h[sj][si+my]           = s_h[sj][si];
		s_t[sj][si-stencilSize]  = s_t[sj][si+my-stencilSize];
		s_t[sj][si+my]           = s_t[sj][si];
		s_p[sj][si-stencilSize]  = s_p[sj][si+my-stencilSize];
		s_p[sj][si+my]           = s_p[sj][si];
		s_m[sj][si-stencilSize]  = s_m[sj][si+my-stencilSize];
		s_m[sj][si+my]           = s_m[sj][si];
		s_l[sj][si-stencilSize]  = s_l[sj][si+my-stencilSize];
		s_l[sj][si+my]           = s_l[sj][si];
	}

	__syncthreads();

	// viscous fluxes derivative
	derDevSharedV2y(&wrk1,s_u[sj],si);
	uYtmp = wrk1*s_m[sj][si];
	derDevSharedV2y(&wrk1,s_v[sj],si);
	vYtmp = wrk1*s_m[sj][si];
	derDevSharedV2y(&wrk1,s_w[sj],si);
	wYtmp = wrk1*s_m[sj][si];
	derDevSharedV2y(&wrk1,s_t[sj],si);
	eYtmp = wrk1*s_l[sj][si];
	__syncthreads();
	derDevSharedV1y(&wrk2,s_l[sj],si); //wrk2 = d (lam) dx
	derDevSharedV1y(&wrk1,s_t[sj],si); //wrk1 = d (t) dx
	eYtmp = eYtmp + wrk1*wrk2;

	//Adding here the terms d (mu) dy * syj; (lambda in case of h in rhse);

	derDevSharedV1y(&wrk2,s_m[sj],si); //wrk2 = d (mu) dx
	uYtmp = uYtmp + wrk2*sij[3][id.g];
	vYtmp = vYtmp + wrk2*sij[4][id.g];
	wYtmp = wYtmp + wrk2*sij[5][id.g];

	// split advection terms

	//Adding here the terms - d (ru phi) dy;

	fluxQuadSharedy(&wrk1,s_r[sj],s_v[sj],si);
	rYtmp = wrk1;
	__syncthreads();
	fluxCubeSharedy(&wrk1,s_r[sj],s_v[sj],s_u[sj],si);
	uYtmp = uYtmp + wrk1;
	__syncthreads();
	fluxCubeSharedy(&wrk1,s_r[sj],s_v[sj],s_v[sj],si);
	vYtmp = vYtmp + wrk1;
	__syncthreads();
	fluxCubeSharedy(&wrk1,s_r[sj],s_v[sj],s_w[sj],si);
	wYtmp = wYtmp + wrk1;
	__syncthreads();
	fluxCubeSharedy(&wrk1,s_r[sj],s_v[sj],s_h[sj],si);
	eYtmp = eYtmp + wrk1;
	__syncthreads();

	// pressure and dilation derivatives
	s_wrk[sj][si] = dil[id.g];
	__syncthreads();
	if (id.j < stencilSize) {
		s_wrk[sj][si-stencilSize]  = s_wrk[sj][si+my-stencilSize];
		s_wrk[sj][si+my]           = s_wrk[sj][si];
	}
	__syncthreads();
	derDevSharedV1y(&wrk2,s_wrk[sj],si);
	derDevShared1y(&wrk1,s_p[sj],si);
	vYtmp = vYtmp - wrk1 + s_m[sj][si]*wrk2*1.0/3.0;

	//viscous dissipation
	s_wrk[sj][si] = s_m[sj][si]*(
					s_u[sj][si]*(  sij[3][id.g]  ) +
					s_v[sj][si]*(  sij[4][id.g]  ) +
					s_w[sj][si]*(  sij[5][id.g]  )
					);
	__syncthreads();
	if (id.j < stencilSize) {
		s_wrk[sj][si-stencilSize]  = s_wrk[sj][si+my-stencilSize];
		s_wrk[sj][si+my]           = s_wrk[sj][si];
	}
	__syncthreads();
	derDevSharedV1y(&wrk2,s_wrk[sj],si);

	rY[id.g] = rYtmp;
	uY[id.g] = uYtmp;
	vY[id.g] = vYtmp;
	wY[id.g] = wYtmp;
	eY[id.g] = eYtmp + wrk2;
}

__global__ void RHSDeviceSharedFlxZ(myprec *rZ, myprec *uZ, myprec *vZ, myprec *wZ, myprec *eZ,
		myprec *r,  myprec *u,  myprec *v,  myprec *w,  myprec *h ,
		myprec *t,  myprec *p,  myprec *mu, myprec *lam,
		myprec *sij[9], myprec *dil) {

	Indices id(threadIdx.x,threadIdx.y,blockIdx.x,blockIdx.y,blockDim.x,blockDim.y);
	id.mkidZFlx();

	int si = id.k + stencilSize;       // local i for shared memory access + halo offset
	int sj = id.tiy;                   // local j for shared memory access

	myprec rZtmp=0;
	myprec uZtmp=0;
	myprec vZtmp=0;
	myprec wZtmp=0;
	myprec eZtmp=0;

	myprec wrk1=0;
	myprec wrk2=0;

	__shared__ myprec s_r[sPencils][mz+stencilSize*2];
	__shared__ myprec s_u[sPencils][mz+stencilSize*2];
	__shared__ myprec s_v[sPencils][mz+stencilSize*2];
	__shared__ myprec s_w[sPencils][mz+stencilSize*2];
	__shared__ myprec s_h[sPencils][mz+stencilSize*2];
	__shared__ myprec s_t[sPencils][mz+stencilSize*2];
	__shared__ myprec s_p[sPencils][mz+stencilSize*2];
	__shared__ myprec s_m[sPencils][mz+stencilSize*2];
	__shared__ myprec s_l[sPencils][mz+stencilSize*2];
	__shared__ myprec s_wrk[sPencils][mz+stencilSize*2];

	s_r[sj][si] = r[id.g];
	s_u[sj][si] = u[id.g];
	s_v[sj][si] = v[id.g];
	s_w[sj][si] = w[id.g];
	s_h[sj][si] = h[id.g];
	s_t[sj][si] = t[id.g];
	s_p[sj][si] = p[id.g];
	s_m[sj][si] = mu[id.g];
	s_l[sj][si] = lam[id.g];
	__syncthreads();

	// fill in periodic images in shared memory array
	if (id.k < stencilSize) {
		s_r[sj][si-stencilSize]  = s_r[sj][si+mz-stencilSize];
		s_r[sj][si+mz]           = s_r[sj][si];
		s_u[sj][si-stencilSize]  = s_u[sj][si+mz-stencilSize];
		s_u[sj][si+mz]           = s_u[sj][si];
		s_v[sj][si-stencilSize]  = s_v[sj][si+mz-stencilSize];
		s_v[sj][si+mz]           = s_v[sj][si];
		s_w[sj][si-stencilSize]  = s_w[sj][si+mz-stencilSize];
		s_w[sj][si+mz]           = s_w[sj][si];
		s_h[sj][si-stencilSize]  = s_h[sj][si+mz-stencilSize];
		s_h[sj][si+mz]           = s_h[sj][si];
		s_t[sj][si-stencilSize]  = s_t[sj][si+mz-stencilSize];
		s_t[sj][si+mz]           = s_t[sj][si];
		s_p[sj][si-stencilSize]  = s_p[sj][si+mz-stencilSize];
		s_p[sj][si+mz]           = s_p[sj][si];
		s_m[sj][si-stencilSize]  = s_m[sj][si+mz-stencilSize];
		s_m[sj][si+mz]           = s_m[sj][si];
		s_l[sj][si-stencilSize]  = s_l[sj][si+mz-stencilSize];
		s_l[sj][si+mz]           = s_l[sj][si];
	}

	__syncthreads();

	// viscous fluxes derivative
	derDevSharedV2z(&wrk1,s_u[sj],si);
	uZtmp = wrk1*s_m[sj][si];
	derDevSharedV2z(&wrk1,s_v[sj],si);
	vZtmp = wrk1*s_m[sj][si];
	derDevSharedV2z(&wrk1,s_w[sj],si);
	wZtmp = wrk1*s_m[sj][si];
	derDevSharedV2z(&wrk1,s_t[sj],si);
	eZtmp = wrk1*s_l[sj][si];
	__syncthreads();
	derDevSharedV1z(&wrk2,s_l[sj],si); //wrk2 = d (lam) dz
	derDevSharedV1z(&wrk1,s_t[sj],si); //wrk1 = d (t) dx
	eZtmp = eZtmp + wrk1*wrk2;

	//Adding here the terms d (mu) dz * szj; (lambda in case of h in rhse);

	derDevSharedV1z(&wrk2,s_m[sj],si); //wrk2 = d (mu) dz
	uZtmp = uZtmp + wrk2*sij[6][id.g];
	vZtmp = vZtmp + wrk2*sij[7][id.g];
	wZtmp = wZtmp + wrk2*sij[8][id.g];

	// split advection terms

	//Adding here the terms - d (ru phi) dz;

	fluxQuadSharedz(&wrk1,s_r[sj],s_w[sj],si);
	rZtmp = wrk1;
	__syncthreads();
	fluxCubeSharedz(&wrk1,s_r[sj],s_w[sj],s_u[sj],si);
	uZtmp = uZtmp + wrk1;
	__syncthreads();
	fluxCubeSharedz(&wrk1,s_r[sj],s_w[sj],s_v[sj],si);
	vZtmp = vZtmp + wrk1;
	__syncthreads();
	fluxCubeSharedz(&wrk1,s_r[sj],s_w[sj],s_w[sj],si);
	wZtmp = wZtmp + wrk1;
	__syncthreads();
	fluxCubeSharedz(&wrk1,s_r[sj],s_w[sj],s_h[sj],si);
	eZtmp = eZtmp + wrk1;
	__syncthreads();

	// pressure and dilation derivatives
	s_wrk[sj][si] = dil[id.g];
	__syncthreads();
	if (id.k < stencilSize) {
		s_wrk[sj][si-stencilSize]  = s_wrk[sj][si+mz-stencilSize];
		s_wrk[sj][si+mz]           = s_wrk[sj][si];
	}
	__syncthreads();
	derDevSharedV1z(&wrk2,s_wrk[sj],si);
	derDevShared1z(&wrk1,s_p[sj],si);
	wZtmp = wZtmp - wrk1 + s_m[sj][si]*wrk2*1.0/3.0;

	//viscous dissipation
	s_wrk[sj][si] = s_m[sj][si]*(
					s_u[sj][si]*(  sij[6][id.g]  ) +
					s_v[sj][si]*(  sij[7][id.g]  ) +
					s_w[sj][si]*(  sij[8][id.g]  )
					);
	__syncthreads();
	if (id.k < stencilSize) {
		s_wrk[sj][si-stencilSize]  = s_wrk[sj][si+mz-stencilSize];
		s_wrk[sj][si+mz]           = s_wrk[sj][si];
	}
	__syncthreads();
	derDevSharedV1z(&wrk2,s_wrk[sj],si);

	rZ[id.g] = rZtmp;
	uZ[id.g] = uZtmp;
	vZ[id.g] = vZtmp;
	wZ[id.g] = wZtmp;
	eZ[id.g] = eZtmp + wrk2;
}

__global__ void RHSDeviceFullYL(myprec *rY, myprec *uY, myprec *vY, myprec *wY, myprec *eY,
		myprec *r,  myprec *u,  myprec *v,  myprec *w,  myprec *h ,
		myprec *t,  myprec *p,  myprec *mu, myprec *lam,
		myprec *sij[9], myprec *dil) {

	Indices id(threadIdx.x,threadIdx.y,blockIdx.x,blockIdx.y,blockDim.x,blockDim.y);

	int sum  = id.biy * mx * my + id.bix*id.bdx + id.tix;

	derDevV1yL(d_workY1,u,id);
	derDevV1yL(uY,d_workY1,id);
	__syncthreads();

	derDevV1yL(d_workY1,v,id);
	derDevV1yL(vY,d_workY1,id);
	__syncthreads();

	derDevV1yL(d_workY1,w,id);
	derDevV1yL(wY,d_workY1,id);
	__syncthreads();

	derDevV1yL(d_workY1    ,t,id);
	derDevV1yL(eY,d_workY1 ,id);
	__syncthreads();

	derDevV1yL(d_workY2,lam,id); //d_work2 = d (lam) dy
	for (int j = id.tiy; j < my; j += id.bdy) {
		int glb = sum + j * mx ;
		uY[glb] = uY[glb]*mu[glb];
		vY[glb] = vY[glb]*mu[glb];
		wY[glb] = wY[glb]*mu[glb];
		eY[glb] = eY[glb]*lam[glb]+ d_workY1[glb]*d_workY2[glb];
	}

	__syncthreads();

	//Adding here the terms d (phi) dy * ( d (mu) dy); (lambda in case of t in rhse);

	derDevV1yL(d_workY2,mu,id); //d_work2 = d (mu) dy
	for (int j = id.tiy; j < my; j += id.bdy) {
		int glb = sum + j * mx ;
		uY[glb] = uY[glb] + d_workY2[glb]*sij[3][glb];
		vY[glb] = vY[glb] + d_workY2[glb]*sij[4][glb];
		wY[glb] = wY[glb] + d_workY2[glb]*sij[5][glb];
	}

	// pressure derivative and dilation derivative
	__syncthreads();
	derDevV1yL(d_workY2,  p,id);
	derDevV1yL(d_workY1,dil,id);
	for (int j = id.tiy; j < my; j += id.bdy) {
		int glb = sum + j * mx ;
		vY[glb] = vY[glb] - d_workY2[glb] + mu[glb]*d_workY1[glb]*1.0/3.0;
	}

	//viscous dissipation
	for (int j = id.tiy; j < my; j += id.bdy) {
		int glb = sum + j * mx ;
		d_workY2[glb] =  mu[glb]*(
					u[glb]*(  sij[3][glb]  ) +
					v[glb]*(  sij[4][glb]  ) +
					w[glb]*(  sij[5][glb]  )
					);
	}
	__syncthreads();
	derDevV1yL(d_workY1,d_workY2,id);
	for (int j = id.tiy; j < my; j += id.bdy) {
		int glb = sum + j * mx ;
		eY[glb] = eY[glb] + d_workY1[glb];
	}

}


__global__ void RHSDeviceFullZL(myprec *rZ, myprec *uZ, myprec *vZ, myprec *wZ, myprec *eZ,
		   myprec *r,  myprec *u,  myprec *v,  myprec *w,  myprec *h ,
		   myprec *t,  myprec *p,  myprec *mu, myprec *lam,
		   myprec *sij[9], myprec *dil) {

	Indices id(threadIdx.x,threadIdx.y,blockIdx.x,blockIdx.y,blockDim.x,blockDim.y);

	int sum = id.biy * mx + id.bix*id.bdx + id.tix;


	derDevV1zL(d_workZ1,u,id);
	derDevV1zL(uZ,d_workZ1,id);
	__syncthreads();

	derDevV1zL(d_workZ1,v,id);
	derDevV1zL(vZ,d_workZ1,id);
	__syncthreads();

	derDevV1zL(d_workZ1,w,id);
	derDevV1zL(wZ,d_workZ1,id);
	__syncthreads();

	derDevV1zL(d_workZ1    ,t,id);
	derDevV1zL(eZ,d_workZ1 ,id);
	__syncthreads();

	derDevV1zL(d_workZ2,lam,id); //d_work2 = d (lam) dz
	__syncthreads();
	for (int k = id.tiy; k < mz; k += id.bdy) {
		int glb = k * mx * my + sum;
		uZ[glb] = uZ[glb]*mu[glb];
		vZ[glb] = vZ[glb]*mu[glb];
		wZ[glb] = wZ[glb]*mu[glb];
		eZ[glb] = eZ[glb]*lam[glb] + d_workZ2[glb]*d_workZ1[glb];
	}

	__syncthreads();

	//Adding here the terms d (phi) dz * ( d (mu) dz -0.5 * rw); (lambda in case of h in rhse);

	derDevV1zL(d_workZ2,mu,id); //d_work2 = d (mu) dz
	for (int k = id.tiy; k < mz; k += id.bdy) {
		int glb = k * mx * my + sum;
		uZ[glb] = uZ[glb] + d_workZ2[glb]*sij[6][glb];
		vZ[glb] = vZ[glb] + d_workZ2[glb]*sij[7][glb];
		wZ[glb] = wZ[glb] + d_workZ2[glb]*sij[8][glb];
	}

	// pressure derivative and dilation derivative
	__syncthreads();
	derDevV1zL(d_workZ2,p  ,id);
	derDevV1zL(d_workZ1,dil,id);
	for (int k = id.tiy; k < mz; k += id.bdy) {
		int glb = k * mx * my + sum;
		wZ[glb] = wZ[glb] - d_workZ2[glb] + mu[glb]*d_workZ1[glb]*1.0/3.0;
	}

	//viscous dissipation
	for (int k = id.tiy; k < mz; k += id.bdy) {
		int glb = k * mx * my + sum;
		d_workZ2[glb] =  mu[glb]*(
					u[glb]*(  sij[6][glb]  ) +
					v[glb]*(  sij[7][glb]  ) +
					w[glb]*(  sij[8][glb]  )
					);
	}
	__syncthreads();
	derDevV1zL(d_workZ1,d_workZ2,id);  // d_work = d (mu dvdz) dy
	for (int k = id.tiy; k < mz; k += id.bdy) {
		int glb = k * mx * my + sum;
		eZ[glb] = eZ[glb] + d_workZ1[glb];
	}

}


__global__ void FLXDeviceY(myprec *rY, myprec *uY, myprec *vY, myprec *wY, myprec *eY,
		myprec *r,  myprec *u,  myprec *v,  myprec *w,  myprec *h ,
		myprec *t,  myprec *p,  myprec *mu, myprec *lam,
		myprec *sij[9], myprec *dil) {

	Indices id(threadIdx.x,threadIdx.y,blockIdx.x,blockIdx.y,blockDim.x,blockDim.y);
	id.mkidYFlx();

	int si = id.j + stencilSize;       // local i for shared memory access + halo offset
	int sj = id.tiy;                   // local j for shared memory access

	myprec wrk1=0;

	__shared__ myprec s_r[sPencils][my+stencilSize*2];
	__shared__ myprec s_u[sPencils][my+stencilSize*2];
	__shared__ myprec s_v[sPencils][my+stencilSize*2];
	__shared__ myprec s_w[sPencils][my+stencilSize*2];
	__shared__ myprec s_h[sPencils][my+stencilSize*2];
	s_r[sj][si] = r[id.g];
	s_u[sj][si] = u[id.g];
	s_v[sj][si] = v[id.g];
	s_w[sj][si] = w[id.g];
	s_h[sj][si] = h[id.g];
	__syncthreads();

	// fill in periodic images in shared memory array
	if (id.j < stencilSize) {
		s_r[sj][si-stencilSize]  = s_r[sj][si+my-stencilSize];
		s_r[sj][si+my]           = s_r[sj][si];
		s_u[sj][si-stencilSize]  = s_u[sj][si+my-stencilSize];
		s_u[sj][si+my]           = s_u[sj][si];
		s_v[sj][si-stencilSize]  = s_v[sj][si+my-stencilSize];
		s_v[sj][si+my]           = s_v[sj][si];
		s_w[sj][si-stencilSize]  = s_w[sj][si+my-stencilSize];
		s_w[sj][si+my]           = s_w[sj][si];
		s_h[sj][si-stencilSize]  = s_h[sj][si+my-stencilSize];
		s_h[sj][si+my]           = s_h[sj][si];
	}

	__syncthreads();

	fluxQuadSharedG(&wrk1,s_r[sj],s_v[sj],si,d_dy);
	rY[id.g] = wrk1;
	__syncthreads();
	fluxCubeSharedG(&wrk1,s_r[sj],s_v[sj],s_u[sj],si,d_dy);
	uY[id.g] = wrk1;
	__syncthreads();
	fluxCubeSharedG(&wrk1,s_r[sj],s_v[sj],s_v[sj],si,d_dy);
	vY[id.g] = wrk1;
	__syncthreads();
	fluxCubeSharedG(&wrk1,s_r[sj],s_v[sj],s_w[sj],si,d_dy);
	wY[id.g] = wrk1;
	__syncthreads();
	fluxCubeSharedG(&wrk1,s_r[sj],s_v[sj],s_h[sj],si,d_dy);
	eY[id.g] = wrk1;
	__syncthreads();

}


__global__ void FLXDeviceZ(myprec *rZ, myprec *uZ, myprec *vZ, myprec *wZ, myprec *eZ,
		myprec *r,  myprec *u,  myprec *v,  myprec *w,  myprec *h ,
		myprec *t,  myprec *p,  myprec *mu, myprec *lam,
		myprec *sij[9], myprec *dil) {

	Indices id(threadIdx.x,threadIdx.y,blockIdx.x,blockIdx.y,blockDim.x,blockDim.y);
	id.mkidZFlx();

	int si = id.k + stencilSize;       // local i for shared memory access + halo offset
	int sj = id.tiy;                   // local j for shared memory access

	myprec wrk1=0;

	__shared__ myprec s_r[sPencils][mz+stencilSize*2];
	__shared__ myprec s_u[sPencils][mz+stencilSize*2];
	__shared__ myprec s_v[sPencils][mz+stencilSize*2];
	__shared__ myprec s_w[sPencils][mz+stencilSize*2];
	__shared__ myprec s_h[sPencils][mz+stencilSize*2];
	s_r[sj][si] = r[id.g];
	s_u[sj][si] = u[id.g];
	s_v[sj][si] = v[id.g];
	s_w[sj][si] = w[id.g];
	s_h[sj][si] = h[id.g];
	__syncthreads();

	// fill in periodic images in shared memory array
	if (id.k < stencilSize) {
		s_r[sj][si-stencilSize]  = s_r[sj][si+mz-stencilSize];
		s_r[sj][si+mz]           = s_r[sj][si];
		s_u[sj][si-stencilSize]  = s_u[sj][si+mz-stencilSize];
		s_u[sj][si+mz]           = s_u[sj][si];
		s_v[sj][si-stencilSize]  = s_v[sj][si+mz-stencilSize];
		s_v[sj][si+mz]           = s_v[sj][si];
		s_w[sj][si-stencilSize]  = s_w[sj][si+mz-stencilSize];
		s_w[sj][si+mz]           = s_w[sj][si];
		s_h[sj][si-stencilSize]  = s_h[sj][si+mz-stencilSize];
		s_h[sj][si+mz]           = s_h[sj][si];
	}

	__syncthreads();

	//Adding here the terms - d (ru phi) dx;

	fluxQuadSharedG(&wrk1,s_r[sj],s_w[sj],si,d_dz);
	rZ[id.g] = wrk1;
	__syncthreads();
	fluxCubeSharedG(&wrk1,s_r[sj],s_w[sj],s_u[sj],si,d_dz);
	uZ[id.g] = wrk1;
	__syncthreads();
	fluxCubeSharedG(&wrk1,s_r[sj],s_w[sj],s_v[sj],si,d_dz);
	vZ[id.g] = wrk1;
	__syncthreads();
	fluxCubeSharedG(&wrk1,s_r[sj],s_w[sj],s_w[sj],si,d_dz);
	wZ[id.g] = wrk1;
	__syncthreads();
	fluxCubeSharedG(&wrk1,s_r[sj],s_w[sj],s_h[sj],si,d_dz);
	eZ[id.g] = wrk1;
	__syncthreads();
}


__device__ void initRHS() {
	checkCudaDev( cudaMalloc((void**)&d_workY1,mx*my*mz*sizeof(myprec)) );
	checkCudaDev( cudaMalloc((void**)&d_workY2,mx*my*mz*sizeof(myprec)) );

	checkCudaDev( cudaMalloc((void**)&d_workZ1,mx*my*mz*sizeof(myprec)) );
	checkCudaDev( cudaMalloc((void**)&d_workZ2,mx*my*mz*sizeof(myprec)) );

}


__device__ void clearRHS() {
	checkCudaDev( cudaFree(d_workY1) );
	checkCudaDev( cudaFree(d_workY2) );

	checkCudaDev( cudaFree(d_workZ1) );
	checkCudaDev( cudaFree(d_workZ2) );

}
