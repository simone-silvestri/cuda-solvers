
#ifndef CUDA_GLOBALS_H_
#define CUDA_GLOBALS_H_

#include "globals.h"
#include <stdio.h>
#include <assert.h>
#define myprec double


// Convenience function for checking CUDA runtime API results
// can be wrapped around any runtime API call. No-op in release builds.
inline
cudaError_t checkCuda(cudaError_t result)
{
#if defined(DEBUG) || defined(_DEBUG)
  if (result != cudaSuccess) {
    fprintf(stderr, "CUDA Runtime Error: %s\n", cudaGetErrorString(result));
    assert(result == cudaSuccess);
  }
#endif
  return result;
}

inline
__device__ cudaError_t checkCudaDev(cudaError_t result)
{
#if defined(DEBUG) || defined(_DEBUG)
  if (result != cudaSuccess) {
    fprintf(stderr, "CUDA Runtime Error: %s\n", cudaGetErrorString(result));
    assert(result == cudaSuccess);
  }
#endif
  return result;
}

// shared memory tiles will be m*-by-*Pencils
// sPencils is used when each thread calculates the derivative at one point
// lPencils is used for coalescing in y and z where each thread has to 
//     calculate the derivative at mutiple points

#if mx==1 || my==1 
const int sPencils = 1;
#else
const int sPencils = 2;  // small # pencils
#endif
#if mx==1 || my==1 || mz==1
const int lPencils = 1;  
#else
const int lPencils = 32;  // large # pencils
#endif

#define lPencilx   0
#define lPencilY   1
#define lPencilZ   1

extern __constant__ myprec dcoeffF[stencilSize];
extern __constant__ myprec dcoeffS[stencilSize+1];
extern __constant__ myprec d_dt, d_dx, d_dy, d_dz, d_d2x, d_d2y, d_d2z;

extern __constant__ dim3 d_grid[3], grid0;
extern __constant__ dim3 d_block[3], block0;

extern __device__ myprec d_r[mx*my*mz];
extern __device__ myprec d_u[mx*my*mz];
extern __device__ myprec d_v[mx*my*mz];
extern __device__ myprec d_w[mx*my*mz];
extern __device__ myprec d_e[mx*my*mz];
extern __device__ myprec d_m[mx*my*mz];
extern __device__ myprec d_l[mx*my*mz];


#endif
