#include <stdlib.h>
#include <math.h>
#include <limits.h>
#include <float.h>

#include "rsm.h"


/*-- Constants ---------------------------------------------------------------*/

const double TOLERANCE = 1e-7;
enum
{
  NONBASIC_LOWER = 1,
  NONBASIC_UPPER = -1,
  NONBASIC_FREE = 2,
  BASIC = 0
};


/*-- Construction and destruction --------------------------------------------*/

void new_model(model *M, int nrows, int nvars, int nonzeroes)
{
  M->nvars = nvars;
  M->nrows = nrows;
  M->nonzeroes = nonzeroes;

  M->indexes = calloc(nonzeroes+1, sizeof(int));
  M->row_starts = calloc(nrows+2, sizeof(int));
  M->elements = calloc(nonzeroes+1, sizeof(double));

  M->b = calloc(nrows+1, sizeof(double));
  M->c = calloc(nvars+1, sizeof(double));
  M->xl = calloc(nvars+1, sizeof(double));
  M->xu = calloc(nvars+1, sizeof(double));
}


void free_model(model *M)
{
  free(M->indexes);
  free(M->row_starts);
  free(M->elements);

  free(M->b);
  free(M->c);
  free(M->xl);
  free(M->xu);
}


void new_instance(instance *I, int nrows, int nvars)
{
  int total_vars = nrows + nvars;

  I->TOLERANCE = TOLERANCE;

  I->status = calloc(total_vars, sizeof(int));
  I->basics = calloc(nrows, sizeof(int));
  I->basic_cycles = calloc(nvars, sizeof(int));

  I->initial_costs = calloc(nvars, sizeof(double));
  I->costs = I->initial_costs;
  I->x = calloc(total_vars, sizeof(double));
  I->xu = calloc(total_vars, sizeof(double));
  I->xl = calloc(total_vars, sizeof(double));

  I->basic_costs = calloc(nrows, sizeof(double));
  I->pi = calloc(nrows, sizeof(double));
  I->reduced_costs = calloc(nvars, sizeof(double));
  I->gradient = calloc(nrows, sizeof(double));
  I->Binverse = calloc(nrows * nrows, sizeof(double));
}


void free_instance(instance *I)
{
  free(I->status);
  free(I->basics);
  free(I->basic_cycles);

  free(I->initial_costs);
  free(I->x);
  free(I->xu);
  free(I->xl);

  free(I->basic_costs);
  free(I->pi);
  free(I->reduced_costs);
  free(I->gradient);
  free(I->Binverse);
}


/*-- Computation parts -------------------------------------------------------*/

static void compute_pi(const model *M, instance *I)
{
  /* pi = basic_costs' * Binverse */
  const int nrows = M->nrows;
  const double *basic_costs = I->basic_costs;
  const double *Bi = I->Binverse;
  const double TOL = I->TOLERANCE;
  double *pi = I->pi;

  int i;

  for (i = 0; i != nrows; ++i) pi[i] = 0.0;
  for (i = 0; i != nrows; ++i)
  {
    double c = basic_costs[i];
    if (fabs(c) > TOL)
    {
      int j;
      for (j = 0; j != nrows; ++j)
        pi[j] += c * Bi[i*nrows + j];
    }
  }
}


static void compute_reduced_cost(const model *M, instance *I)
{
  /* reduced cost = cost - pi' * A */
  const int nvars = M->nvars, nrows = M->nrows;
  const int *indexes = M->indexes;
  const double *elements = M->elements;
  const int *row_starts = M->row_starts;
  const int *status = I->status;
  const double *costs = I->costs;
  const double *pi = I->pi;
  const double TOL = I->TOLERANCE;
  double *reduced_costs = I->reduced_costs;

  int i, j;

  /* initialise with costs (phase 2) or zero (phase 1 and basic variables) */
  for (i = 0; i != nvars; ++i)
    reduced_costs[i] = status[i] != 0 ? costs[i] : 0.0;

  /* Compute rcs 'sideways' - work through elements of A using each one once
     the downside is that we write to reduced_costs frequently */
  for (i = 0; i != nrows; ++i)
  {
    const double p = pi[i];
    if (fabs(p) > TOL)
    {
      for (j = row_starts[i]; j != row_starts[i+1]; ++j)
      {
        const int k = indexes[j];
        if (status[k] != 0)
          reduced_costs[k] = reduced_costs[k] - p * elements[j];
      }
    }
  }
}


static int find_entering_variable(const model *M, instance *I)
{
  /* Find the variable with the "lowest" reduced cost, keeping in mind that it might be at its upper bound */
  const int nvars = M->nvars;
  const int *status = I->status;
  const int *basic_cycles = I->basic_cycles;
  const double *reduced_costs = I->reduced_costs;
  const double TOL = -I->TOLERANCE;

  int cycles = INT_MAX;
  int entering_index = -2;
  double minrc = 0.0;

  int i;

  for (i = 0; i != nvars; ++i)
  {
    int s = status[i];
    double rc;
    if (s == NONBASIC_FREE)
      rc = -fabs(reduced_costs[i]);
    else
      rc = s * reduced_costs[i];

    int c = basic_cycles[i];
    if ((c < cycles && rc < TOL) || (c == cycles && rc < minrc))
    {
      minrc = rc;
      cycles = basic_cycles[i];
      entering_index = i;
    }
  }
  return entering_index;
}


static void compute_gradient(const model *M, instance *I)
{
  /* gradient = Binverse * entering column of A */
  const int nrows = M->nrows;
  const int *indexes = M->indexes;
  const double *elements = M->elements;
  const int *row_starts = M->row_starts;
  const int entering_index = I->entering_index;
  const double *Bi = I->Binverse;
  double *gradient = I->gradient;

  int i, j;
  
  for (i = 0; i != nrows; ++i) gradient[i] = 0.0;
  for (i = 0; i != nrows; ++i)
  {
    int found = 0;
    double v;
    for (j = row_starts[i]; j != row_starts[i+1]; ++j)
    {
      int column = indexes[j];
      if (column == entering_index)
      {
        found = 1;
        v = elements[j];
        break;
      }
      else if (column > entering_index)
        break;
    }
    if (found)
    {
      for (j = 0; j != nrows; ++j)
        gradient[j] += v * Bi[j*nrows + i];
    }
  }
}


static int find_leaving_variable(const model *M, instance *I, double *max_change_out, int *to_lower_out)
{
  const int nvars = M->nvars, nrows = M->nrows;
  const int entering_index = I->entering_index;
  const int *status = I->status;
  const int *basics = I->basics;
  const double *reduced_costs = I->reduced_costs;
  const double *x = I->x;
  const double *xl = I->xl;
  const double *xu = I->xu;
  const double *gradient = I->gradient;
  const double TOL = I->TOLERANCE;

  double s;
  switch (status[entering_index])
  {
    case NONBASIC_LOWER: s =  1.0; break;
    case NONBASIC_UPPER: s = -1.0; break;
    case NONBASIC_FREE:
      s = reduced_costs[entering_index] > 0.0 ? -1.0 : 1.0;
      break;
  }

  double max_change = xu[entering_index] - xl[entering_index];
  int leaving_index = -2;
  int to_lower = 0;

  int i;

  for (i = 0; i != nrows; ++i)
  {
    double g = gradient[i] * -s;
    if (fabs(g) > TOL)
    {
      int j = basics[i];
      int found_bound = 0;
      double bound = 0;

      if (g > 0.0)
      {
        if (xu[j] < DBL_MAX)
        {
          bound = xu[j];
          found_bound = 1;
        }
      }
      else
      {
        if (xl[j] > -DBL_MAX)
        {
          bound = xl[j];
          found_bound = 1;
        }
      }

      if (found_bound)
      {
        double z = (bound - x[j]) / g;
        /* we prefer to get rid of artificials when we can */
        if (z < max_change || (j >= nvars && z <= max_change))
        {
          max_change = z;
          leaving_index = i;
          to_lower = g < 0.0;
        }
      }
    }
  }

  *max_change_out = max_change * s;
  *to_lower_out = to_lower;
  return leaving_index;
}


static void update_variables(const model *M, instance *I)
{
  const int nrows = M->nrows;
  const int *basics = I->basics;
  const double c = I->max_change;
  const double *gradient = I->gradient;
  double *x = I->x;
  
  int i;
  
  for (i = 0; i != nrows; ++i)
  {
    int j = basics[i];
    x[j] = x[j] - c * gradient[i];
  }
}


static void update_Binverse(const model *M, instance *I)
{
  const int nrows = M->nrows;
  const int li = I->leaving_index;
  const double *gradient = I->gradient;
  double *Bi = I->Binverse;

  double ilg = 1.0 / gradient[li];

  int i, j;

  for (i = 0; i != nrows; ++i)
  {
    if (i != li)
    {
      double gr = gradient[i] * ilg;
      for (j = 0; j != nrows; ++j)
        Bi[i*nrows + j] -= gr * Bi[li*nrows + j];
    }
  }
  for (j = 0; j != nrows; ++j)
    Bi[li*nrows + j] *= ilg;
}


/*-- Solve -------------------------------------------------------------------*/

const char *rsm_solve(const model *M, instance *I)
{
  const int nvars = M->nvars, nrows = M->nrows;
  double TOLERANCE = I->TOLERANCE;
  
  I->iterations = 0;
  I->phase = 1;

  int i;

  for (;;)
  {
    ++I->iterations;
    if (I->iterations > 10000)
      return "Iteration limit";
 
    compute_pi(M, I);
    compute_reduced_cost(M, I);
    I->entering_index = find_entering_variable(M, I);

    if (I->entering_index < 0)
    {
      if (I->phase == 1)
      {
        for (i = 0; i != nrows; ++i)
        {
          if (I->basics[i] > nvars && fabs(I->x[I->basics[i] ]) > TOLERANCE)
            return "Infeasible";
        }
        I->costs = M->c;
        for (i = 0; i != nrows; ++i)
        {
          if (I->basics[i] <= nvars)
            I->basic_costs[i] = M->c[I->basics[i] ];
        }
        I->phase = 2;
      }
      else
        break;  /* optimal */
    }
    else
    {
      I->basic_cycles[I->entering_index] += 1;

      compute_gradient(M, I);
      int to_lower;
      I->leaving_index = find_leaving_variable(M, I, &I->max_change, &to_lower);

      if (I->phase == 2 && I->max_change >= DBL_MAX / 2.0)
        return "unbounded";

      if (fabs(I->max_change) > TOLERANCE)
      {
        for (i = 0; i != nvars; ++i)
          I->basic_cycles[i] = 0;
      }

      update_variables(M, I);
      I->x[I->entering_index] = I->x[I->entering_index] + I->max_change;

      if (I->leaving_index >= 0)
      {
        update_Binverse(M, I);

        int rli = I->basics[I->leaving_index];
        I->x[rli] = to_lower ? I->xl[rli] : I->xu[rli];
        I->status[rli] = to_lower ? NONBASIC_LOWER : NONBASIC_UPPER;

        I->basics[I->leaving_index] = I->entering_index;
        I->basic_costs[I->leaving_index] = I->costs[I->entering_index];

        I->status[I->entering_index] = BASIC;
      }
      else
        I->status[I->entering_index] = -I->status[I->entering_index];
    }
  }

  double objective = 0.0;
  for (i = 0; i != nvars; ++i)
    objective += I->x[i] * M->c[i];
  I->objective = objective;

  return "optimal";
}


/*-- EOF ---------------------------------------------------------------------*/

