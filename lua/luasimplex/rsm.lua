local math = require("math")
local error, select = error, select

local luasimplex = require("luasimplex")
local iarray, darray = luasimplex.iarray, luasimplex.darray

local rsm = {}
setfenv(1, rsm)


-- Constants -------------------------------------------------------------------

local TOLERANCE = 1e-7
local NONBASIC_LOWER = 1
local NONBASIC_UPPER = -1
local NONBASIC_FREE = 2
local BASIC = 0


-- Computation parts -----------------------------------------------------------

local function compute_pi(M, I)
  -- pi = basic_costs' * Binverse
  local nrows, pi, Bi, TOL = M.nrows, I.pi, I.Binverse, I.TOLERANCE
  
  for i = 1, nrows do pi[i] = 0 end
  for i = 1, nrows do
    local c = I.basic_costs[i]
    if math.abs(c) > TOL then
      for j = 1, nrows do
        pi[j] = pi[j] + c * Bi[(i-1)*nrows + j]
      end
    end
  end
end


local function compute_reduced_cost(M, I)
  -- reduced cost = cost - pi' * A 
  local reduced_costs, status, TOL = I.reduced_costs, I.status, I.TOLERANCE

  -- initialise with costs (phase 2) or zero (phase 1 and basic variables)
  for i = 1, M.nvars do
    reduced_costs[i] = status[i] ~= 0 and I.costs[i] or 0
  end

  -- Compute rcs 'sideways' - work through elements of A using each one once
  -- the downside is that we write to reduced_costs frequently
  for i = 1, M.nrows do
    local p = I.pi[i]
    if math.abs(p) > TOL then
      local a = M.A[i]
      local indexes, values = a.indexes, a.values
      for j = 1, a.elements do
        local k = indexes[j]
        if status[k] ~= 0 then
          reduced_costs[k] = reduced_costs[k] - p * values[j]
        end        
      end
    end
  end
end


local function find_entering_variable(M, I)
  local TOL = -I.TOLERANCE
  -- Find the variable with the "lowest" reduced cost, keeping in mind that it might be at its upper bound

  local cycles, minrc, entering_index = math.huge
  for i = 1, M.nvars do
    local s, rc = I.status[i]
    if s == NONBASIC_FREE then
      rc = -math.abs(I.reduced_costs[i])
    else
      rc = s * I.reduced_costs[i]
    end
    local c = I.basic_cycles[i]
    if (c < cycles and rc < TOL) or (c == cycles and rc < minrc) then
      minrc = rc
      cycles = I.basic_cycles[i]
      entering_index = i
    end
  end
  return entering_index
end


function compute_gradient(M, I, entering_index, gradient)
  -- gradient = Binverse * entering row of a
  local nrows, Bi = M.nrows, I.Binverse

  if gradient then
    for i = 1, nrows do gradient[i] = 0 end
  else
    gradient = darray(nrows, 0)
  end

  for i = 1, nrows do
    local a = M.A[i]
    local indexes = a.indexes
    local v
    for j = 1, a.elements do
      local column = indexes[j]
      if column == entering_index then
        v = a.values[j]
        break
      elseif column > entering_index then
        break
      end
    end
    if v then
      for j = 1, nrows do
        gradient[j] = gradient[j] + v * Bi[(j-1)*nrows + i]
      end
    end
  end
  return gradient
end


function find_leaving_variable(M, I, entering_index, gradient)
  local TOL = I.TOLERANCE

  local s = I.status[entering_index]
  if s == NONBASIC_FREE then
    s = I.reduced_costs[entering_index] > 0 and -1 or 1
  end

  local max_change, leaving_index, to_lower = I.xu[entering_index] - I.xl[entering_index]

  for i = 1, M.nrows do
    local g = gradient[i] * -s
    if math.abs(g) > TOL then
      local j, bound = I.basics[i]

      if g > 0 then
        if I.xu[j] < math.huge then bound = I.xu[j] end
      else
        if I.xl[j] > -math.huge then bound = I.xl[j] end
      end

      if bound then
        local z = (bound - I.x[j]) / g
        -- we prefer to get rid of artificials when we can
        if z < max_change or (j > M.nvars and z <= max_change) then
          max_change = z
          leaving_index = i
          to_lower = g < 0
        end
      end
    end
  end
  
  return leaving_index, (leaving_index and max_change * s) or 0, to_lower
end


local function update_variables(M, I)
  local c = I.max_change
  for i = 1, M.nrows do
    local j = I.basics[i]
    I.x[j] = I.x[j] - c * I.gradient[i]
  end
end


local function update_Binverse(M, I)
  local nrows, li, Bi = M.nrows, I.leaving_index, I.Binverse

  local lg = I.gradient[li]
  for i = 1, nrows do
    if i ~= li then
      local gr = I.gradient[i] / lg
      for j = 1, nrows do
        Bi[(i-1)*nrows + j] = Bi[(i-1)*nrows + j] - gr * Bi[(li-1)*nrows + j]
      end
    end
  end
  for j = 1, nrows do
    Bi[(li-1)*nrows + j] = Bi[(li-1)*nrows + j] / lg
  end
end


-- Initialisation --------------------------------------------------------------

local function initialise_real_variables(M, I)
  local nvars, nrows, tvars = M.nvars, M.nrows, M.nvars + M.nrows
  I.x = darray(tvars)
  I.xu = darray(tvars)
  I.xl = darray(tvars)
  I.status = darray(tvars)
  I.basic_cycles = iarray(nvars, 0)

  for i = 1, nvars do
    I.xu[i], I.xl[i] = M.xu[i], M.xl[i]
    if M.xl[i] == -math.huge and M.xu[i] == math.huge then
      I.x[i] = 0
      I.status[i] = NONBASIC_FREE
    elseif math.abs(M.xl[i]) < math.abs(M.xu[i]) then
      I.x[i] = M.xl[i]
      I.status[i] = NONBASIC_LOWER
    else
      I.x[i] = M.xu[i]
      I.status[i] = NONBASIC_UPPER
    end
  end
end


local function initialise_artificial_variables(M, I)
  local nvars, nrows = M.nvars, M.nrows
  I.basics = iarray(nrows)
  I.basic_costs = darray(nrows)

  for i = 1, nrows do
    local z = M.b[i]
    local a = M.A[i]
    for j = 1, a.elements do
      z = z - a.values[j] * I.x[a.indexes[j]]
    end
    local k = nvars + i
    I.x[k] = z
    I.status[k] = BASIC
    I.basics[i] = k
    if z < 0 then
      I.basic_costs[i], I.xl[k], I.xu[k] = -1, -math.huge, 0
    else
      I.basic_costs[i], I.xl[k], I.xu[k] = 1, 0, math.huge
    end
    if M.variable_names and M.constraint_names then
      M.variable_names[k] = M.constraint_names[i].."_ARTIFICIAL"
    end
  end
end


function initialise(M, S)
  local nrows, nvars = M.nrows, M.nvars
  local I = {}
  
  if not S.TOLERANCE then S.TOLERANCE = TOLERANCE end
  I.TOLERANCE = S.TOLERANCE

  initialise_real_variables(M, I)
  initialise_artificial_variables(M, I)

  I.Binverse = darray(nrows^2)
  for i = 1, nrows do I.Binverse[(i-1)*nrows + i] = 1 end

  I.pi = darray(nrows, 0)
  I.costs = darray(nvars, 0)
  I.reduced_costs = darray(nvars, 0)
  I.gradient = darray(nrows, 0)

  return I
end


-- Solve -----------------------------------------------------------------------

function solve(M, S)
  local I = initialise(M, S)
  local TOLERANCE = I.TOLERANCE
  
  local nvars, nrows = M.nvars, M.nrows
  I.iterations = 0
  I.phase = 1
  local monitor = S.monitor

  while true do
    I.iterations = I.iterations + 1
    if monitor then monitor(M, I, S, "iteration") end

    compute_pi(M, I)
    compute_reduced_cost(M, I)
    I.entering_index = find_entering_variable(M, I)
    if monitor then monitor(M, I, S, "entering_variable") end

    if not I.entering_index then
      if I.phase == 1 then
        for i = 1, nrows do
          if I.basics[i] > nvars and math.abs(I.x[I.basics[i] ]) > TOLERANCE  then
            if S.diagnose then S.diagnose(M, I, S, "infeasible") end
            error("Infeasible")
          end
        end
        I.costs = M.c
        for i = 1, nrows do
          if I.basics[i] <= nvars then
            I.basic_costs[i] = M.c[I.basics[i] ]
          end
        end
        I.phase = 2
      else
        break  -- optimal
      end
    else

      I.basic_cycles[I.entering_index] = I.basic_cycles[I.entering_index] + 1

      compute_gradient(M, I, I.entering_index, I.gradient)
      local to_lower
      I.leaving_index, I.max_change, to_lower = find_leaving_variable(M, I, I.entering_index, I.gradient)
      if monitor then monitor(M, I, S, "leaving_variable") end

      if I.phase == 2 and I.max_change >= math.huge / 2 then
        if S.diagnose then S.diagnose(M, I, S, "unbounded") end
        error("Unbounded")
      end

      if (math.abs(I.max_change) > I.TOLERANCE) then
        for i = 1, nvars do
          I.basic_cycles[i] = 0
        end
      end

      update_variables(M, I)
      I.x[I.entering_index] = I.x[I.entering_index] + I.max_change

      if I.leaving_index then
        update_Binverse(M, I)

        local rli = I.basics[I.leaving_index]
        I.x[rli] = to_lower and I.xl[rli] or I.xu[rli]
        I.status[rli] = to_lower and NONBASIC_LOWER or NONBASIC_UPPER

        I.basics[I.leaving_index] = I.entering_index
        I.basic_costs[I.leaving_index] = I.costs[I.entering_index]

        I.status[I.entering_index] = BASIC
      else
        I.status[I.entering_index] = -I.status[I.entering_index]
      end
    end
  end

  local objective = 0
  for i = 1, nvars do
    objective = objective + I.x[i] * M.c[i]
  end

  return objective, I.x, I.iterations
end


--------------------------------------------------------------------------------

return rsm


-- EOF -------------------------------------------------------------------------

