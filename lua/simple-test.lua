local luasimplex = require("luasimplex")
local rsm = require("luasimplex.rsm")

local M =
{
  -- number of variables
  nvars = 4,
  -- number of constraints
  nrows = 2,
  indexes = luasimplex.iarray(6, 1, 2, 3, 1, 2, 4),
  elements = luasimplex.darray(6, 1, 2, 1, 2, 1, 1),
  row_starts = luasimplex.iarray(3, 1, 4, 7),
  c = luasimplex.darray(4, -1, -1, 0, 0),
  xl = luasimplex.darray(4, 0, 0, 0, 0),
  xu = luasimplex.darray(4, math.huge, math.huge, math.huge, math.huge),
  b = luasimplex.darray(2, 3, 3),
}

local I = luasimplex.new_instance(M.nrows, M.nvars)
rsm.initialise(M, I, {})

objective, x = rsm.solve(M, I, {})

io.stderr:write(("Objective: %g\n"):format(objective))
io.stderr:write("  x:")
for i = 1, M.nvars do io.stderr:write((" %g"):format(x[i])) end
io.stderr:write("\n")


-- EOF -------------------------------------------------------------------------

