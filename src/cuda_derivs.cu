
/**
 * Copyright 1993-2012 NVIDIA Corporation.  All rights reserved.
 *
 * Please refer to the NVIDIA end user license agreement (EULA) associated
 * with this source code for terms and conditions that govern your use of
 * this software. Any use, reproduction, disclosure, or distribution of
 * this software and related documentation outside the terms of the EULA
 * is strictly prohibited.
 */
#include <stdio.h>
#include <stdlib.h>
#include <cuda.h>
#include "cuda_functions.h"
#include "cuda_globals.h"

__device__ void fluxQuadx(myprec *df, myprec *f, myprec *g, Indices id) {
	int si = id.i + stencilSize;       // local i for shared memory access + halo offset
	int sj = id.tiy;                   // local j for shared memory access

	__shared__ myprec s_f[sPencils][mx+stencilSize*2]; // 4-wide halo
	__shared__ myprec s_g[sPencils][mx+stencilSize*2]; // 4-wide halo
	__shared__ myprec s_a[sPencils][mx+stencilSize*2][stencilSize]; // 4-wide halo
	__shared__ myprec flx[sPencils][mx+stencilSize*2]; // 4-wide halo

	s_f[sj][si] = f[id.g];
	s_g[sj][si] = g[id.g];
	flx[sj][si] = 0.0;
	__syncthreads();

	// fill in periodic images in shared memory array
	if (id.i < stencilSize) {
		s_f[sj][si-stencilSize]  = s_f[sj][si+mx-stencilSize];
		s_f[sj][si+mx]           = s_f[sj][si];
		s_g[sj][si-stencilSize]  = s_g[sj][si+mx-stencilSize];
		s_g[sj][si+mx]           = s_g[sj][si];
		flx[sj][si-stencilSize]  = 0.0;
		flx[sj][si+mx]  		 = 0.0;
	}
	__syncthreads();

	for (int it=0; it<stencilSize; it++) {
		s_a[sj][si][it] = - dcoeffF[stencilSize-1-it]*(s_f[sj][si] + s_f[sj][si+it+1])*(s_g[sj][si] + s_g[sj][si+it+1])*d_dx;
	}
	__syncthreads();

	if (id.i < stencilSize) {
		for (int it=0; it<stencilSize; it++) {
				s_a[sj][si-stencilSize][it] = s_a[sj][si+mx-stencilSize][it];
				s_a[sj][si+mx][it]          = s_a[sj][si][it];
		}
	}

	__syncthreads();

	for (int it=0; it<stencilSize; it++)
		for (int lt=0; lt<it; lt++)
			flx[sj][si] += s_a[sj][si-lt][it];

	__syncthreads();

	if (id.i < stencilSize) {
		flx[sj][si-stencilSize]  = flx[sj][si+mx-stencilSize];
		flx[sj][si+mx]           = flx[sj][si];

	}
	__syncthreads();

	df[id.g] = -0.5*(flx[sj][si] - flx[sj][si-1]);

}

__device__ void fluxCubex(myprec *df, myprec *f, myprec *g, myprec *h, Indices id) {
	int si = id.i + stencilSize;       // local i for shared memory access + halo offset
	int sj = id.tiy;                   // local j for shared memory access

	__shared__ myprec s_f[sPencils][mx+stencilSize*2]; // 4-wide halo
	__shared__ myprec s_g[sPencils][mx+stencilSize*2]; // 4-wide halo
	__shared__ myprec s_h[sPencils][mx+stencilSize*2]; // 4-wide halo
	__shared__ myprec s_a[sPencils][mx+stencilSize*2][stencilSize]; // 4-wide halo
	__shared__ myprec flx[sPencils][mx+stencilSize*2]; // 4-wide halo

	s_f[sj][si] = f[id.g];
	s_g[sj][si] = g[id.g];
	s_h[sj][si] = h[id.g];
	flx[sj][si] = 0.0;

	__syncthreads();

	// fill in periodic images in shared memory array
	if (id.i < stencilSize) {
		s_f[sj][si-stencilSize]  = s_f[sj][si+mx-stencilSize];
		s_f[sj][si+mx]           = s_f[sj][si];
		s_g[sj][si-stencilSize]  = s_g[sj][si+mx-stencilSize];
		s_g[sj][si+mx]           = s_g[sj][si];
		s_h[sj][si-stencilSize]  = s_h[sj][si+mx-stencilSize];
		s_h[sj][si+mx]           = s_h[sj][si];
		flx[sj][si-stencilSize]  = 0.0;
		flx[sj][si+mx]  		 = 0.0;
	}
	__syncthreads();

	for (int it=0; it<stencilSize; it++) {
		s_a[sj][si][it] = - dcoeffF[stencilSize-1-it]*(s_f[sj][si] + s_f[sj][si+it+1])*(s_g[sj][si] + s_g[sj][si+it+1])*(s_h[sj][si] + s_h[sj][si+it+1])*d_dx;
	}
	__syncthreads();

	if (id.i < stencilSize) {
		for (int it=0; it<stencilSize; it++) {
				s_a[sj][si-stencilSize][it] = s_a[sj][si+mx-stencilSize][it];
				s_a[sj][si+mx][it]          = s_a[sj][si][it];
		}
	}

	__syncthreads();

	for (int it=0; it<stencilSize; it++)
		for (int lt=0; lt<it; lt++)
			flx[sj][si] += s_a[sj][si-lt][it];

	__syncthreads();

	if (id.i < stencilSize) {
		flx[sj][si-stencilSize]  = flx[sj][si+mx-stencilSize];
		flx[sj][si+mx]           = flx[sj][si];

	}
	__syncthreads();

	df[id.g] = -0.25*(flx[sj][si] - flx[sj][si-1]);

}

__device__ void derDev1x(myprec *df, myprec *f, Indices id)
{

	int si = id.i + stencilSize;       // local i for shared memory access + halo offset
	int sj = id.tiy;                   // local j for shared memory access

	__shared__ myprec s_f[sPencils][mx+stencilSize*2]; // 4-wide halo

	s_f[sj][si] = f[id.g];

	__syncthreads();

	// fill in periodic images in shared memory array
	if (id.i < stencilSize) {
		s_f[sj][si-stencilSize]  = s_f[sj][si+mx-stencilSize]; // CHANGED SIMONE: s_f[sj][si+mx-stencilSize-1];
		s_f[sj][si+mx]           = s_f[sj][si];                // CHANGED SIMONE: s_f[sj][si+1];
	}

	__syncthreads();

	myprec dftemp = 0.0;
	for (int it=0; it<stencilSize; it++)  {
		dftemp += dcoeffF[it]*(s_f[sj][si+it-stencilSize]-s_f[sj][si+stencilSize-it])*d_dx;
	}

	df[id.g] = dftemp;
	__syncthreads();
}

__device__ void derDev1y(myprec *df, myprec *f, Indices id)
{
	__shared__ myprec s_f[my+stencilSize*2][sPencils];

	int si = id.tix;
	int sj = id.j + stencilSize;

	s_f[sj][si] = f[id.g];

	__syncthreads();

	if (id.j < stencilSize) {
		s_f[sj-stencilSize][si]  = s_f[sj+my-stencilSize][si];
		s_f[sj+my][si]           = s_f[sj][si];
	}

	__syncthreads();

	myprec dftemp = 0.0;
	for (int jt=0; jt<stencilSize; jt++)  {
		dftemp += dcoeffF[jt]*(s_f[sj+jt-stencilSize][si]-s_f[sj+stencilSize-jt][si])*d_dy;
	}

	df[id.g] = dftemp;
	__syncthreads();

}

__device__ void derDev1z(myprec *df, myprec *f, Indices id)
{


	__shared__ myprec s_f[mz+stencilSize*2][sPencils];

	int si = id.tix;
	int sk = id.k + stencilSize;

	s_f[sk][si] = f[id.g];

	__syncthreads();

	if (id.k < stencilSize) {
		s_f[sk-stencilSize][si]  = s_f[sk+mz-stencilSize][si];
		s_f[sk+mz][si]           = s_f[sk][si];
	}

	__syncthreads();

	myprec dftemp = 0.0;
	for (int kt=0; kt<stencilSize; kt++)  {
		dftemp += dcoeffF[kt]*(s_f[sk+kt-stencilSize][si]-s_f[sk+stencilSize-kt][si])*d_dz;
	}

	df[id.g] = dftemp;

	__syncthreads();


//	if(id.g==2081100) {
//		for(int kt=0; kt<stencilSize; kt++)
//			printf("index\t %d \t left\t %le \t right\t %le\t %le\n",kt,s_f[sk+kt-stencilSize][si],s_f[sk-kt+stencilSize][si],df[id.g]);
//	}
//	__syncthreads();

}

__device__ void derDev2x(myprec *d2f, myprec *f, Indices id)
{

	int si = id.i + stencilSize;       // local i for shared memory access + halo offset
	int sj = id.tiy;                   // local j for shared memory access

	__shared__ myprec s_f[sPencils][mx+stencilSize*2]; // 4-wide halo

	s_f[sj][si] = f[id.g];

	__syncthreads();

	// fill in periodic images in shared memory array
	if (id.i < stencilSize) {
		s_f[sj][si-stencilSize]  = s_f[sj][si+mx-stencilSize]; // CHANGED SIMONE: s_f[sj][si+mx-stencilSize-1];
		s_f[sj][si+mx]           = s_f[sj][si];                // CHANGED SIMONE: s_f[sj][si+1];
	}

	__syncthreads();

	d2f[id.g] = dcoeffS[stencilSize]*s_f[sj][si]*d_d2x;
	for (int it=0; it<stencilSize; it++)  {
		d2f[id.g] += dcoeffS[it]*(s_f[sj][si+it-stencilSize]+s_f[sj][si+stencilSize-it])*d_d2x;
	}
	__syncthreads();

}

__device__ void derDev2y(myprec *d2f, myprec *f, Indices id)
{
	__shared__ myprec s_f[my+stencilSize*2][sPencils];

	int si = id.tix;
	int sj = id.j + stencilSize;

	s_f[sj][si] = f[id.g];

	__syncthreads();

	if (id.j < stencilSize) {
		s_f[sj-stencilSize][si]  = s_f[sj+my-stencilSize][si];
		s_f[sj+my][si]           = s_f[sj][si];
	}

	__syncthreads();

	myprec dftemp = dcoeffS[stencilSize]*s_f[sj][si]*d_d2y;
	for (int jt=0; jt<stencilSize; jt++)  {
		dftemp += dcoeffS[jt]*(s_f[sj+jt-stencilSize][si]+s_f[sj+stencilSize-jt][si])*d_d2y;
	}
	d2f[id.g] = dftemp;

	__syncthreads();
}

__device__ void derDev2z(myprec *d2f, myprec *f, Indices id)
{


	__shared__ myprec s_f[mz+stencilSize*2][sPencils];

	int si = id.tix;
	int sk = id.k + stencilSize;

	s_f[sk][si] = f[id.g];

	__syncthreads();

	if (id.k < stencilSize) {
		s_f[sk-stencilSize][si]  = s_f[sk+mz-stencilSize][si];
		s_f[sk+mz][si]           = s_f[sk][si];
	}

	__syncthreads();

	myprec dftemp = dcoeffS[stencilSize]*s_f[sk][si]*d_d2z;
	for (int kt=0; kt<stencilSize; kt++)  {
		dftemp += dcoeffS[kt]*(s_f[sk+kt-stencilSize][si]+s_f[sk+stencilSize-kt][si])*d_d2z;
	}

	d2f[id.g] = dftemp;

	__syncthreads();
}

__device__ void derDev1xL(myprec *df, myprec *f, Indices id)
{
  __shared__ myprec s_f[lPencils][mx+stencilSize*2]; // 4-wide halo

  int i     = id.tix;
  int jBase = id.bix*lPencils;
  int k     = id.biy;
  int si    = i + stencilSize; // local i for shared memory access + halo offset

  for (int sj = id.tiy; sj < lPencils; sj += id.bdy) {
    int globalIdx = k * mx * my + (jBase + sj) * mx + i;
    s_f[sj][si] = f[globalIdx];
  }

  __syncthreads();

  // fill in periodic images in shared memory array
  if (i < stencilSize) {
    for (int sj = id.tiy; sj < lPencils; sj += id.bdy) {
      s_f[sj][si-stencilSize]  = s_f[sj][si+mx-stencilSize];
      s_f[sj][si+mx] = s_f[sj][si];
    }
  }

  __syncthreads();

  for (int sj = id.tiy; sj < lPencils; sj += id.bdy) {
	  int globalIdx = k * mx * my + (jBase + sj) * mx + i;
	  myprec dftemp = 0.0;
	  for (int it=0; it<stencilSize; it++)  {
		  dftemp += dcoeffF[it]*(s_f[sj][si+it-stencilSize]-s_f[sj][si+stencilSize-it])*d_dx;
	  }
	  df[globalIdx] = dftemp;
  }
}

__device__ void derDev1yL(myprec *df, myprec *f, Indices id)
{
  __shared__ myprec s_f[my+stencilSize*2][lPencils];

  int i  = id.bix*id.bdx + id.tix;
  int k  = id.biy;
  int si = id.tix;

  for (int j = id.tiy; j < my; j += id.bdy) {
    int globalIdx = k * mx * my + j * mx + i;
    int sj = j + stencilSize;
    s_f[sj][si] = f[globalIdx];
  }

  __syncthreads();

  int sj = id.tiy + stencilSize;
  if (sj < stencilSize*2) {
     s_f[sj-stencilSize][si]  = s_f[sj+my-stencilSize][si];
     s_f[sj+my][si] = s_f[sj][si];
  }

  __syncthreads();

  for (int j = id.tiy; j < my; j += id.bdy) {
    int globalIdx = k * mx * my + j * mx + i;
    int sj = j + stencilSize;
	myprec dftemp = 0.0;
	for (int jt=0; jt<stencilSize; jt++)  {
		dftemp += dcoeffF[jt]*(s_f[sj+jt-stencilSize][si]-s_f[sj+stencilSize-jt][si])*d_dy;
	}
	df[globalIdx] = dftemp;
  }
}

__device__ void derDev1zL(myprec *df, myprec *f, Indices id)
{
  __shared__ myprec s_f[mz+stencilSize*2][lPencils];

  int i  = id.bix*id.bdx + id.tix;
  int j  = id.biy;
  int si = id.tix;

  for (int k = id.tiy; k < mz; k += id.bdy) {
    int globalIdx = k * mx * my + j * mx + i;
    int sk = k + stencilSize;
    s_f[sk][si] = f[globalIdx];
  }

  __syncthreads();

  int sk = id.tiy + stencilSize;
  if (sk < stencilSize*2) {
     s_f[sk-stencilSize][si]  = s_f[sk+mz-stencilSize][si];
     s_f[sk+mz][si] = s_f[sk][si];
  }

  __syncthreads();

  for (int k = id.tiy; k < mz; k += id.bdy) {
    int globalIdx = k * mx * my + j * mx + i;
    int sk = k + stencilSize;
	myprec dftemp = 0.0;
	for (int kt=0; kt<stencilSize; kt++)  {
		dftemp += dcoeffF[kt]*(s_f[sk+kt-stencilSize][si]-s_f[sk+stencilSize-kt][si])*d_dz;
	}
	df[globalIdx] = dftemp;
  }
}

__device__ void derDev2xL(myprec *d2f, myprec *f, Indices id)
{
  __shared__ myprec s_f[lPencils][mx+stencilSize*2]; // 4-wide halo

  int i     = id.tix;
  int jBase = id.bix*lPencils;
  int k     = id.biy;
  int si    = i + stencilSize; // local i for shared memory access + halo offset

  for (int sj = id.tiy; sj < lPencils; sj += id.bdy) {
    int globalIdx = k * mx * my + (jBase + sj) * mx + i;
    s_f[sj][si] = f[globalIdx];
  }

  __syncthreads();

  // fill in periodic images in shared memory array
  if (i < stencilSize) {
    for (int sj = id.tiy; sj < lPencils; sj += id.bdy) {
      s_f[sj][si-stencilSize]  = s_f[sj][si+mx-stencilSize];
      s_f[sj][si+mx] = s_f[sj][si];
    }
  }

  __syncthreads();

  for (int sj = id.tiy; sj < lPencils; sj += id.bdy) {
	  int globalIdx = k * mx * my + (jBase + sj) * mx + i;
	  myprec dftemp = dcoeffS[stencilSize]*s_f[sj][si]*d_d2x;
	  for (int it=0; it<stencilSize; it++)  {
		  dftemp += dcoeffS[it]*(s_f[sj][si+it-stencilSize]+s_f[sj][si+stencilSize-it])*d_d2x;
	  }
	  d2f[globalIdx] = dftemp;
  }
}

__device__ void derDev2yL(myprec *d2f, myprec *f, Indices id)
{
  __shared__ myprec s_f[my+stencilSize*2][lPencils];

  int i  = id.bix*id.bdx + id.tix;
  int k  = id.biy;
  int si = id.tix;

  for (int j = id.tiy; j < my; j += id.bdy) {
    int globalIdx = k * mx * my + j * mx + i;
    int sj = j + stencilSize;
    s_f[sj][si] = f[globalIdx];
  }

  __syncthreads();

  int sj = id.tiy + stencilSize;
  if (sj < stencilSize*2) {
     s_f[sj-stencilSize][si]  = s_f[sj+my-stencilSize][si];
     s_f[sj+my][si] = s_f[sj][si];
  }

  __syncthreads();

  for (int j = id.tiy; j < my; j += id.bdy) {
    int globalIdx = k * mx * my + j * mx + i;
    int sj = j + stencilSize;
	myprec dftemp = dcoeffS[stencilSize]*s_f[sj][si]*d_d2y;
	for (int jt=0; jt<stencilSize; jt++)  {
		dftemp += dcoeffS[jt]*(s_f[sj+jt-stencilSize][si]+s_f[sj+stencilSize-jt][si])*d_d2y;
	}
	d2f[globalIdx] = dftemp;
  }
}

__device__ void derDev2zL(myprec *d2f, myprec *f, Indices id)
{
  __shared__ myprec s_f[mz+stencilSize*2][lPencils];

  int i  = id.bix*id.bdx + id.tix;
  int j  = id.biy;
  int si = id.tix;

  for (int k = id.tiy; k < mz; k += id.bdy) {
    int globalIdx = k * mx * my + j * mx + i;
    int sk = k + stencilSize;
    s_f[sk][si] = f[globalIdx];
  }

  __syncthreads();

  int sk = id.tiy + stencilSize;
  if (sk < stencilSize*2) {
     s_f[sk-stencilSize][si]  = s_f[sk+mz-stencilSize][si];
     s_f[sk+mz][si] = s_f[sk][si];
  }

  __syncthreads();

  for (int k = id.tiy; k < mz; k += id.bdy) {
    int globalIdx = k * mx * my + j * mx + i;
    int sk = k + stencilSize;
	myprec dftemp = dcoeffS[stencilSize]*s_f[sk][si]*d_d2z;
	for (int kt=0; kt<stencilSize; kt++)  {
		dftemp += dcoeffS[kt]*(s_f[sk+kt-stencilSize][si]+s_f[sk+stencilSize-kt][si])*d_d2z;
	}
	d2f[globalIdx] = dftemp;
  }
}

__device__ void derDevShared1x(myprec *df, myprec *s_f, int si)
{
	*df = 0.0;
	for (int it=0; it<stencilSize; it++)  {
		*df += dcoeffF[it]*(s_f[si+it-stencilSize]-s_f[si+stencilSize-it])*d_dx;
	}

	__syncthreads();
}

__device__ void derDevShared2x(myprec *d2f, myprec *s_f, int si)
{

	*d2f = dcoeffS[stencilSize]*s_f[si]*d_d2x;
	for (int it=0; it<stencilSize; it++)  {
		*d2f += dcoeffS[it]*(s_f[si+it-stencilSize]+s_f[si+stencilSize-it])*d_d2x;
	}

	__syncthreads();

}
