/*
 * cuda_math.h
 *
 *  Created on: Apr 15, 2021
 *      Author: simone
 */

#ifndef CUDA_MATH_H_
#define CUDA_MATH_H_


__global__ void deviceCpy(myprec *a, myprec *b);
__global__ void deviceBlocker();
__global__ void deviceCpyOne(myprec *a, myprec *b);
__global__ void deviceSum(myprec *a, myprec *b, myprec *c);
__global__ void deviceSumOne(myprec *a, myprec *b, myprec *c);
__global__ void deviceSub(myprec *a, myprec *b, myprec *c);
__global__ void deviceMul(myprec *a, myprec *b, myprec *c);
__global__ void deviceDiv(myprec *a, myprec *b, myprec *c);
__global__ void deviceDivOne(myprec *a, myprec *b, myprec *c);
__global__ void deviceSca(myprec *a, myprec *bx, myprec *by, myprec *bz, myprec *cx, myprec *cy, myprec *cz);
__device__ void volumeIntegral(myprec *gout, myprec *var);
__device__ void reduceToOne(myprec *gout, myprec *var);
__device__ void reduceToMax(myprec *gout, myprec *var);
__device__ void reduceToMin(myprec *gout, myprec *var);
__global__ void integrateThreads (myprec *gOut, myprec *gArr, int arraySize);
__global__ void AverageThreads (myprec *gOut, myprec *gArr, int arraySize);
__global__ void reduceThreads (myprec *gOut, myprec *gArr, int arraySize);
__global__ void minOfThreads (myprec *gOut, myprec *gArr, int arraySize);
__global__ void maxOfThreads (myprec *gOut, myprec *gArr, int arraySize);
__device__ unsigned int findPreviousPowerOf2(unsigned int n);
void hostReduceToMin(myprec *gOut, myprec *var, Communicator rk);
void hostVolumeIntegral(myprec *gOut, myprec *var, Communicator rk);
void hostVolumeAverage(myprec *gOut, myprec *var, Communicator rk);

#endif /* CUDA_MATH_H_ */
