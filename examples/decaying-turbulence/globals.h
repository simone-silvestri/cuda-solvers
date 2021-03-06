
#ifndef GLOBALS_H_
#define GLOBALS_H_

#define myprec double
#define MPI_myprec MPI_DOUBLE

#include "math.h"
#include "main.h"
#include <stdlib.h>
#include <stdio.h>

//Remember: Run always the code with num-tasks-per-node = num-GPUs-per-node. Otherwise it will not work!
#define pRow 1
#define pCol 1

//Remember : viscous stencil should ALWAYS be smaller than the advective stencil!!! (otherwise errors in how you load global into shared memory)
#define stencilSize 4  // the order is double the stencilSize (advective fluxes stencil)
#define stencilVisc 4  // the order is double the stencilVisc (viscous fluxes stencil)

#define Lx       (2.0*M_PI)
#define Ly       (2.0*M_PI)
#define Lz       (2.0*M_PI)
#define mx_tot   128
#define my_tot   128
#define mz_tot   128
#define nsteps   101
#define nfiles	 100
#define CFL      0.5f
#define restart  -1
#if restart<0
	const int restartFile = -1;
#else
	const int restartFile = restart;
#endif

#define Re       1600.f
#define Pr       1.0f
#define gamma    1.4f
#define Ma       0.1f
#define viscexp  1.0
#define Ec       ((gamma - 1.f)*Ma*Ma)
#define Rgas     (1.f/(gamma*Ma*Ma))


const myprec TwallTop = 1.0;
const myprec TwallBot = 1.0;

#define forcing       (false)
#define periodicX     (true)
#define nonUniformX   (false)
#define useStreams    (false)   // true might give a little speedup (it might also be harmful in terms of performance in certain occasions) very bad for memory footprint

const double stretch = 3.0;

#define checkCFLcondition 10
#define checkBulk 10

#define mx (mx_tot)
#define my (my_tot/pRow)
#define mz (mz_tot/pCol)

#define idx(i,j,k) \
		({ ( k )*mx*my +( j )*mx + ( i ); })

#if pRow*pCol>1
const int multiGPU = 1;
#else
const int multiGPU = 0;
#endif

#if stencilSize==1
const double coeffF[] = {-1.0/2.0};
const double coeffS[] = {1.0, -2.0};
#elif stencilSize==2
const double coeffF[] = { 1.0/12.0, -2.0/3.0};
const double coeffS[] = {-1.0/12.0,  4.0/3.0, -5.0/2.0};
#elif stencilSize==3
const double coeffF[] = {-1.0/60.0,  3.0/20.0, -3.0/4.0};
const double coeffS[] = { 1.0/90.0, -3.0/20.0,  3.0/2.0, -49.0/18.0};
#elif stencilSize==4
const double coeffF[] = { 1.0/280.0, -4.0/105.0,  1.0/5.0, -4.0/5.0};
const double coeffS[] = {-1.0/560.0,  8.0/315.0, -1.0/5.0,  8.0/5.0,  -205.0/72.0};
#endif

#if stencilVisc==1
const double coeffVF[] = {-1.0/2.0};
const double coeffVS[] = {1.0, -2.0};
#elif stencilVisc==2
const double coeffVF[] = { 1.0/12.0, -2.0/3.0};
const double coeffVS[] = {-1.0/12.0,  4.0/3.0, -5.0/2.0};
#elif stencilVisc==3
const double coeffVF[] = {-1.0/60.0,  3.0/20.0, -3.0/4.0};
const double coeffVS[] = { 1.0/90.0, -3.0/20.0,  3.0/2.0, -49.0/18.0};
#elif stencilVisc==4
const double coeffVF[] = { 1.0/280.0, -4.0/105.0,  1.0/5.0, -4.0/5.0};
const double coeffVS[] = {-1.0/560.0,  8.0/315.0, -1.0/5.0,  8.0/5.0,  -205.0/72.0};
#endif

#if useStreams
	const int fin = 3;
#else
	const int fin = 1;
#endif

extern double dt, h_dpdz;

extern double dx,x[mx],xp[mx],xpp[mx],y[my_tot],z[mz_tot];

extern double r[mx*my*mz];
extern double u[mx*my*mz];
extern double v[mx*my*mz];
extern double w[mx*my*mz];
extern double e[mx*my*mz];

#endif
