local rsm = require("luasimplex.rsm")

local M =
{
  -- number of variables
  nvars = 4,
  -- number of constraints
  nrows = 2,
  A =
  {
    {
      elements = 3,
      indexes = rsm.iarray(3, 1, 2, 3),
      values = rsm.darray(3, 1, 2, 1),
    },
    {
      elements = 3,
      indexes = rsm.iarray(3, 1, 2, 4),
      values = rsm.darray(3, 2, 1, 1),
    }
  },
  c = rsm.darray(4, -1, -1, 0, 0),
  xl = rsm.darray(4, 0, 0, 0, 0),
  xu = rsm.darray(4, math.huge, math.huge, math.huge, math.huge),
  b = rsm.darray(2, 3, 3),
}

objective, x = rsm.solve(M, {})

io.stderr:write(("Objective: %g\n"):format(objective))
io.stderr:write("  x:")
for i = 1, M.nvars do io.stderr:write((" %g"):format(x[i])) end
io.stderr:write("\n")


-- EOF -------------------------------------------------------------------------

