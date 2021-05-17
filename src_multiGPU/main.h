#ifndef MAIN_H_
#define MAIN_H_

#include <stdio.h>
#include <stdlib.h>

#define MAX(a,b) ({ __typeof__ (a) _a = (a); __typeof__ (b) _b = (b); _a >= _b ? _a : _b; })
#define MIN(a,b) ({ __typeof__ (a) _a = (a); __typeof__ (b) _b = (b); _a <= _b ? _a : _b; })

class Communicator {
public:
	int nodeRank, rank, jp, jm, kp, km;
	int jstart,jend,kstart,kend;
	void myRank(int rk) {
		rank = rk;
	}
	void printGrid() {
		printf("My Rank is %d with neighbours %d %d %d %d\n",rank,jp,jm,kp,km);
		printf("My Rank is %d with limits     %d %d %d %d\n",rank,jstart,jend,kstart,kend);
	}
};

void writeField(int timestep, Communicator rk);
void initField(int timestep, Communicator rk);
void printRes(Communicator rk);
extern void initCHIT(Communicator rk);
extern void initGrid(Communicator rk);
extern void initChannel(Communicator rk);
extern void calcdt(Communicator rk);
void calcAvgChan(Communicator rk);
void setDerivativeParameters(Communicator rk);
void copyField(int direction);
void checkGpuMem();
void runSimulation(myprec *kin, myprec *enst, myprec *time, Communicator rk);
void initSolver();
void clearSolver();
void solverWrapper(Communicator rk);
void restartWrapper(int restartFile, Communicator rk);
void fillBoundaries(myprec *jm, myprec *jp, myprec *km, myprec *kp, myprec *var, int direction);
void fillBoundariesFive(myprec *jm, myprec *jp, myprec *km, myprec *kp, myprec *r, myprec *u, myprec *v, myprec *w, myprec *e, int direction);
void initHalo();
void destroyHalo();

#endif