/* To run the debugger!!
 * CUDA_VISIBLE_DEVICES="0" cuda-gdb -tui ns
 *  */

#include "globals.h"
#include "cuda_functions.h"
#include "cuda_globals.h"

__constant__ myprec dcoeffF[stencilSize];
__constant__ myprec dcoeffS[stencilSize+1];
__constant__ myprec dcoeffVF[stencilSize];
__constant__ myprec dcoeffVS[stencilSize+1];
__constant__ myprec d_dt, d_dx, d_dy, d_dz, d_d2x, d_d2y, d_d2z;
__constant__ dim3 d_block[5], grid0;
__constant__ dim3 d_grid[5], block0;

dim3 hgrid, hblock;

// host routine to set constant data
void setDerivativeParameters(dim3 &grid, dim3 &block)
{

  // check to make sure dimensions are integral multiples of sPencils
  if ((mx % sPencils != 0) || (my %sPencils != 0) || (mz % sPencils != 0)) {
    printf("'mx', 'my', and 'mz' must be integral multiples of sPencils\n");
    exit(1);
  }

  myprec h_dt = (myprec) 1.e-3; //dt;
  myprec h_dx = (myprec) 1.0/(x[1] - x[0]);
  myprec h_dy = (myprec) 1.0/(y[1] - y[0]);
  myprec h_dz = (myprec) 1.0/(z[1] - z[0]);

  myprec h_d2x = h_dx*h_dx;
  myprec h_d2y = h_dy*h_dy;
  myprec h_d2z = h_dz*h_dz;

  myprec *h_coeffF  = new myprec[stencilSize];
  myprec *h_coeffS  = new myprec[stencilSize+1];
  myprec *h_coeffVF = new myprec[stencilSize];
  myprec *h_coeffVS = new myprec[stencilSize+1];
  
  for (int it=0; it<stencilSize; it++) {
   h_coeffF[it]  = (myprec) coeffF[it];
   h_coeffVF[it] = (myprec) coeffVF[it]; }
  for (int it=0; it<stencilSize+1; it++) {
   h_coeffS[it]  = (myprec) coeffS[it];
   h_coeffVS[it] = (myprec) coeffVS[it]; }

  checkCuda( cudaMemcpyToSymbol(dcoeffF , h_coeffF ,  stencilSize   *sizeof(myprec), 0, cudaMemcpyHostToDevice) );
  checkCuda( cudaMemcpyToSymbol(dcoeffS , h_coeffS , (stencilSize+1)*sizeof(myprec), 0, cudaMemcpyHostToDevice) );
  checkCuda( cudaMemcpyToSymbol(dcoeffVF, h_coeffVF,  stencilSize   *sizeof(myprec), 0, cudaMemcpyHostToDevice) );
  checkCuda( cudaMemcpyToSymbol(dcoeffVS, h_coeffVS, (stencilSize+1)*sizeof(myprec), 0, cudaMemcpyHostToDevice) );
  

  checkCuda( cudaMemcpyToSymbol(d_dt  , &h_dt  ,   sizeof(myprec), 0, cudaMemcpyHostToDevice) );
  checkCuda( cudaMemcpyToSymbol(d_dx  , &h_dx  ,   sizeof(myprec), 0, cudaMemcpyHostToDevice) );
  checkCuda( cudaMemcpyToSymbol(d_dy  , &h_dy  ,   sizeof(myprec), 0, cudaMemcpyHostToDevice) );
  checkCuda( cudaMemcpyToSymbol(d_dz  , &h_dz  ,   sizeof(myprec), 0, cudaMemcpyHostToDevice) );
  checkCuda( cudaMemcpyToSymbol(d_d2x , &h_d2x ,   sizeof(myprec), 0, cudaMemcpyHostToDevice) );
  checkCuda( cudaMemcpyToSymbol(d_d2y , &h_d2y ,   sizeof(myprec), 0, cudaMemcpyHostToDevice) );
  checkCuda( cudaMemcpyToSymbol(d_d2z , &h_d2z ,   sizeof(myprec), 0, cudaMemcpyHostToDevice) );

  dim3 *h_grid, *h_block;
  h_grid  = new dim3[5];
  h_block = new dim3[5];


  // X-grid
#if lPencilX == 1
  dim3 gridX  = dim3(my / lPencils, mz, 1);
  dim3 blockX = dim3(mx, sPencils, 1);
#else
  dim3 gridX  = dim3(my / sPencils, mz, 1);
  dim3 blockX = dim3(mx, sPencils, 1);     
#endif

  // Y-grid
#if lPencilY == 1
  dim3 gridY  = dim3(mx / lPencils, mz, 1);
  dim3 blockY = dim3(lPencils, my * sPencils / lPencils, 1);
#else
  dim3 gridY  = dim3(mx / sPencils, mz, 1);
  dim3 blockY = dim3(sPencils, my, 1);     
#endif
  h_grid[3]  = dim3(mx / sPencils, mz, 1);
  h_block[3] = dim3(my + 1, sPencils, 1);

  // Z-grid spencils
#if lPencilZ == 1
  dim3 gridZ  = dim3(mx / lPencils, my, 1);
  dim3 blockZ = dim3(lPencils, mz * sPencils / lPencils, 1);
#else
  dim3 gridZ  = dim3(mx / sPencils, my, 1);
  dim3 blockZ = dim3(sPencils, mz, 1);     
#endif
  h_grid[4]  = dim3(mx / sPencils, my, 1);
  h_block[4] = dim3(mz, sPencils, 1);

  h_grid[0]  =  gridX; h_grid[1]  =  gridY; h_grid[2]  =  gridZ;
  h_block[0] = blockX; h_block[1] = blockY; h_block[2] =  blockZ;

  checkCuda( cudaMemcpyToSymbol(d_grid  , h_grid  , 5*sizeof(dim3), 0, cudaMemcpyHostToDevice) );
  checkCuda( cudaMemcpyToSymbol(d_block , h_block , 5*sizeof(dim3), 0, cudaMemcpyHostToDevice) );

  printf("Grid configuration:\n");
  printf("Grid 0: {%d, %d, %d} blocks. Blocks 0: {%d, %d, %d} threads.\n",h_grid[0].x, h_grid[0].y, h_grid[0].z, h_block[0].x, h_block[0].y, h_block[0].z);
  printf("Grid 1: {%d, %d, %d} blocks. Blocks 1: {%d, %d, %d} threads.\n",h_grid[1].x, h_grid[1].y, h_grid[1].z, h_block[1].x, h_block[1].y, h_block[1].z);
  printf("Grid 2: {%d, %d, %d} blocks. Blocks 2: {%d, %d, %d} threads.\n",h_grid[2].x, h_grid[2].y, h_grid[2].z, h_block[2].x, h_block[2].y, h_block[2].z);
  printf("Grid 3: {%d, %d, %d} blocks. Blocks 1: {%d, %d, %d} threads.\n",h_grid[3].x, h_grid[3].y, h_grid[3].z, h_block[3].x, h_block[3].y, h_block[3].z);
  printf("Grid 4: {%d, %d, %d} blocks. Blocks 2: {%d, %d, %d} threads.\n",h_grid[4].x, h_grid[4].y, h_grid[4].z, h_block[4].x, h_block[4].y, h_block[4].z);
  printf("\n");

  hgrid  = dim3(my / sPencils, mz, 1);
  hblock = dim3(mx, sPencils, 1);

  checkCuda( cudaMemcpyToSymbol(grid0  , &hgrid  , sizeof(dim3), 0, cudaMemcpyHostToDevice) );
  checkCuda( cudaMemcpyToSymbol(block0 , &hblock , sizeof(dim3), 0, cudaMemcpyHostToDevice) );

  grid  = 1;
  block = 1;

  delete [] h_coeffF;
  delete [] h_coeffS;
  delete [] h_coeffVF;
  delete [] h_coeffVS;
  delete [] h_grid;
  delete [] h_block;

}

void copyInit(int direction) {

  myprec *fr  = new myprec[mx*my*mz];
  myprec *fu  = new myprec[mx*my*mz];
  myprec *fv  = new myprec[mx*my*mz];
  myprec *fw  = new myprec[mx*my*mz];
  myprec *fe  = new myprec[mx*my*mz];
  myprec *d_fr, *d_fu, *d_fv, *d_fw, *d_fe;
  int bytes = mx*my*mz * sizeof(myprec);
  checkCuda( cudaMalloc((void**)&d_fr, bytes) );
  checkCuda( cudaMalloc((void**)&d_fu, bytes) );
  checkCuda( cudaMalloc((void**)&d_fv, bytes) );
  checkCuda( cudaMalloc((void**)&d_fw, bytes) );
  checkCuda( cudaMalloc((void**)&d_fe, bytes) );


  if(direction == 1) {

     for (int it=0; it<mx*my*mz; it++)  {
      fr[it] = (myprec) r[it];
      fu[it] = (myprec) u[it];
      fv[it] = (myprec) v[it];
      fw[it] = (myprec) w[it];
      fe[it] = (myprec) e[it];
     }

     // device arrays
     checkCuda( cudaMemcpy(d_fr, fr, bytes, cudaMemcpyHostToDevice) );  
     checkCuda( cudaMemcpy(d_fu, fu, bytes, cudaMemcpyHostToDevice) );  
     checkCuda( cudaMemcpy(d_fv, fv, bytes, cudaMemcpyHostToDevice) );  
     checkCuda( cudaMemcpy(d_fw, fw, bytes, cudaMemcpyHostToDevice) );  
     checkCuda( cudaMemcpy(d_fe, fe, bytes, cudaMemcpyHostToDevice) );  

     initDevice<<<hgrid, hblock>>>(d_fr,d_fu,d_fv,d_fw,d_fe);


  } else {

     checkCuda( cudaMemset(d_fr, 0, bytes) );
     checkCuda( cudaMemset(d_fu, 0, bytes) );
     checkCuda( cudaMemset(d_fv, 0, bytes) );
     checkCuda( cudaMemset(d_fw, 0, bytes) );
     checkCuda( cudaMemset(d_fe, 0, bytes) );

     getResults<<<hgrid, hblock>>>(d_fr,d_fu,d_fv,d_fw,d_fe);

     checkCuda( cudaMemcpy(fr, d_fr, bytes, cudaMemcpyDeviceToHost) );
     checkCuda( cudaMemcpy(fu, d_fu, bytes, cudaMemcpyDeviceToHost) );
     checkCuda( cudaMemcpy(fv, d_fv, bytes, cudaMemcpyDeviceToHost) );
     checkCuda( cudaMemcpy(fw, d_fw, bytes, cudaMemcpyDeviceToHost) );
     checkCuda( cudaMemcpy(fe, d_fe, bytes, cudaMemcpyDeviceToHost) );

     for (int it=0; it<mx*my*mz; it++)  {
      r[it]   = (double) fr[it];
      u[it]   = (double) fu[it];
      v[it]   = (double) fv[it];
      w[it]   = (double) fw[it];
      e[it]   = (double) fe[it];
     }
 
  }
  
  checkCuda( cudaFree(d_fr) );
  checkCuda( cudaFree(d_fu) );
  checkCuda( cudaFree(d_fv) );
  checkCuda( cudaFree(d_fw) );
  checkCuda( cudaFree(d_fe) );
  delete []  fr;  
  delete []  fu;  
  delete []  fv;  
  delete []  fw;  
  delete []  fe;  

}

__global__ void initDevice(myprec *d_fr, myprec *d_fu, myprec *d_fv, myprec *d_fw, myprec *d_fe) {

	int threadsPerBlock  = blockDim.x * blockDim.y;
	int threadNumInBlock = threadIdx.x + blockDim.x * threadIdx.y;
	int blockNumInGrid   = blockIdx.x  + gridDim.x  * blockIdx.y;

	int globalThreadNum = blockNumInGrid * threadsPerBlock + threadNumInBlock;

	d_r[globalThreadNum]   = d_fr[globalThreadNum];
	d_u[globalThreadNum]   = d_fu[globalThreadNum];
	d_v[globalThreadNum]   = d_fv[globalThreadNum];
	d_w[globalThreadNum]   = d_fw[globalThreadNum];
	d_e[globalThreadNum]   = d_fe[globalThreadNum];
}

__global__ void getResults(myprec *d_fr, myprec *d_fu, myprec *d_fv, myprec *d_fw, myprec *d_fe) {

	int threadsPerBlock  = blockDim.x * blockDim.y;
	int threadNumInBlock = threadIdx.x + blockDim.x * threadIdx.y;
	int blockNumInGrid   = blockIdx.x  + gridDim.x  * blockIdx.y;

	int globalThreadNum = blockNumInGrid * threadsPerBlock + threadNumInBlock;

	d_fr[globalThreadNum] = d_r[globalThreadNum];
	d_fu[globalThreadNum] = d_u[globalThreadNum];
	d_fv[globalThreadNum] = d_v[globalThreadNum];
	d_fw[globalThreadNum] = d_w[globalThreadNum];
	d_fe[globalThreadNum] = d_e[globalThreadNum];
}


void checkGpuMem() {

	float free_m;
	size_t free_t,total_t;

	cudaMemGetInfo(&free_t,&total_t);

	free_m =(uint)free_t/1048576.0 ;

	printf ( "mem free %zu\t (%f MB mem)\n",free_t,free_m);

}
