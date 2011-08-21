typedef struct
{
  int nrows, nvars, nonzeroes;
  int *indexes;
  int *row_starts;
  double *elements;
  double *b;
  double *c;
  double *xl, *xu;
} model;

typedef struct
{
  int phase;
  int iterations;
  int entering_index;
  int leaving_index;
  int *status;
  int *basics;
  int *basic_cycles;
  double objective;
  double TOLERANCE;
  double max_change;
  double *initial_costs, *costs;
  double *x, *xl, *xu;
  double *basic_costs;
  double *pi;
  double *reduced_costs;
  double *gradient;
  double *Binverse;
} instance;

void new_model(model *M, int nrows, int nvars, int nonzeroes);
void free_model(model *M);
void new_instance(instance *I, int nrows, int nvars);
void free_instance(instance *I);
const char *rsm_solve(const model *M, instance *I);
