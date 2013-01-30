local io, math, table = require("io"), require("math"), require("table")
local error, ipairs, pairs, tonumber = error, ipairs, pairs, tonumber

local luasimplex = require("luasimplex")
local rsm = require("luasimplex.rsm")


-- Diagnostic calculations -----------------------------------------------------

local function compute_objective(M, I)
  local o = 0
  if I.phase == 1 then
    for i = M.nvars + 1, M.nvars + M.nrows do o = o + I.x[i] end
  else
    for i = 1, M.nvars do o = o + M.c[i] * I.x[i] end
  end
  return o
end


local function check_variable_bounds(M, I, S)
  local failures = {}
  for i = 1, M.nrows + M.nvars do
    local x = I.x[i]
    if (I.xl[i] - x > S.TOLERANCE) or (I.x[i] - x > S.TOLERANCE) or x ~= x then
      failures[#failures+1] = i
    end
  end
  return failures[1] and failures or nil
end


local function check_constraints(M, I, S)
  local indexes, elements, row_starts = M.indexes, M.elements, M.row_starts

  local failures = {}
  for i = 1, M.nrows do
    local c = I.x[M.nvars + i]
    for j = row_starts[i], row_starts[i+1]-1 do
      c = c + elements[j] * I.x[indexes[j] ]
    end
    if math.abs(c - M.b[i]) > S.TOLERANCE then
      failures[#failures+1] = i
    end
  end
  return failures[1] and failures or nil
end


local function check(M, I, S, what)
  if what == "iteration" then
    local variable_failures, constraint_failures = check_variable_bounds(M, I, S), check_constraints(M, I, S)
    if variable_failures then
      luasimplex.error("Bound violation", M, I, S)
    end
    if constraint_failures then
      luasimplex.error("Constraint violation", M, I, S)
    end
  end
end


-- Display variables -----------------------------------------------------------

local function display_variable_name(M, I, i)
  if M.variable_names then
    return ("%d '%s'"):format(i, M.variable_names[i])
  else
    return ("%d"):format(i)
  end
end


local function display_variable_bounds(M, I, i)
  return ("%g <= %g <= %g"):format(I.xl[i], I.x[i], I.xu[i])
end


local status_names =
{
  [-1] = "UPPER",
  [ 0] = "BASIC",
  [ 1] = "LOWER",
  [ 2] = "NBFREE",
}


local function display_variable_reduced_cost(M, I, i)
  return ("%g, %s"):format(I.reduced_costs[i], status_names[I.status[i] ])
end


local function display_variable(M, I, i)
  return display_variable_name(M, I, i)..", "..display_variable_bounds(M, I, i)
end


-- Display constraints ---------------------------------------------------------

local function display_constraint(M, I, c)
  local indexes, elements, row_starts = M.indexes, M.elements, M.row_starts

  local variables, value = {}, 0

  -- assemble a table centred strings describing the variables in the constraint
  for j = row_starts[c], row_starts[c+1]-1 do
    local i = indexes[j]
    value = value + elements[j] * I.x[i]

    local v =
    {
      name = display_variable_name(M, I, i),
      coeff = ("%g"):format(elements[j]),
      bounds = display_variable_bounds(M, I, i),
      rc = display_variable_reduced_cost(M, I, i),
    }

    local w = math.max(#v.name, #v.coeff, #v.bounds, #v.rc)
    local function centre(s)
      return (" "):rep(math.floor((w-#s)/2))..s..(" "):rep(math.floor((w-#s)/2+.5))
    end
    for k, s in pairs(v) do v[k] = centre(s) end

    variables[#variables+1] = v
  end

  -- Write the constraint name
  if M.constraint_names then
    io.stderr:write(("Constraint %4d '%s'"):format(c, M.constraint_names[c]))
  else
    io.stderr:write(("Constraint %4d"):format(c))
  end
  io.stderr:write((": RHS=%.9g, value=%.9g, artificial=%.9g, difference=%g, dual=%g\n"):
    format(M.b[c], value, I.x[M.nvars+c], value + I.x[M.nvars+c] - M.b[c], I.pi[c]))
  
  -- Write the constraint variables, not using more than 120 columns
  local order = {{"coeff", "Coeff    "}, {"name", "Name     "}, {"bounds", "Value    "}, {"rc", "RC,Status"}}
  local lines = {}
  for i, o in ipairs(order) do
    lines[i] = o[2].." |"
  end
  for i, v in ipairs(variables) do
    local len = lines[1]:len() + v[order[1][1] ]:len()
    if len > 120 then
      for i, o in ipairs(order) do
        io.stderr:write(lines[i], "\n")
        lines[i] = o[2].." |"
      end
      io.stderr:write("...\n")
    end
    for i, o in ipairs(order) do
      lines[i] = lines[i].." "..v[o[1] ].." |"
    end
  end
  for i, o in ipairs(order) do
    io.stderr:write(lines[i], "\n")
  end
  io.stderr:write("\n")
end


-- Display ---------------------------------------------------------------------

local function display_iteration(M, I, S)
  io.stderr:write(("Phase %d iteration %d: objective = %g\n"):format(I.phase, I.iterations, compute_objective(M, I)))

  local variable_failures, constraint_failures = check_variable_bounds(M, I, S), check_constraints(M, I, S)
  if variable_failures then
    io.stderr:write("  Bound violation\n")
    for _, i in ipairs(variable_failures) do
      io.stderr:write("    ", display_variable(M, I, i), "\n")
    end
    luasimplex.error("Bound violation", M, I, S)
  end
  if constraint_failures then
    io.stderr:write("  Constraint violation\n")
    for _, i in ipairs(constraint_failures) do
      display_constraint(M, I, i)
    end
    luasimplex.error("Constraint violation", M, I, S)
  end
end


local function display_entering_variable(M, I, S)
  local i = I.entering_index
  if i and i >= 0 then
    io.stderr:write(("  Entering variable %s, rc = %g, cycles = %d\n"):format(display_variable(M, I, i), I.reduced_costs[i], I.basic_cycles[i]))
  else
    io.stderr:write("  No entering variable\n")
  end
end


local function display_leaving_variable(M, I, S)
  local j = I.leaving_index
  if j then
    local i = I.basics[j]
    local s = I.status[I.entering_index]
    if s == 2 then
      s = I.reduced_costs[I.entering_index] > 0 and -1 or 1
    end
    local g = I.gradient[j] * -s
    io.stderr:write(("  Leaving variable %s, gradient = %g, ev step = %g\n"):format(display_variable(M, I, i), g, I.max_change))

    if I.phase == 1 and i <= M.nvars then
      io.stderr:write("  Leaving variable is non-artificial in phase 1\n")
      for k = 1, M.nrows do
        local p = I.basics[k]
        if p > M.nvars then
          local g2 = I.gradient[k] * -s
          if math.abs(g2) > I.TOLERANCE then
            local bound
            if g2 > 0 then
              if I.xu[p] < math.huge then bound = I.xu[p] end
            else
              if I.xl[p] > -math.huge then bound = I.xl[p] end
            end
            if bound then
              local z = (bound - I.x[p]) / g2
              if z <= I.max_change then
                io.stderr:write(("    %s, gradient = %g, limit = %g\n"):format(display_variable(M, I, p), g2, z))
              end
            end
          end
        end
      end
    end
    
    if math.abs(I.max_change) < I.TOLERANCE then
      io.stderr:write("  Degenerate step\n")
      local rcs = {}
      for i = 1, M.nvars do
        local s, rc = I.status[i]
        if s == NONBASIC_FREE then
          rc = -math.abs(I.reduced_costs[i])
        else
          rc = s * I.reduced_costs[i]
        end
        if rc < -I.TOLERANCE then
          rcs[#rcs+1] = { rc=rc, index=i }
        end
      end
      table.sort(rcs, function(a, b) return a.rc < b.rc end)
      for i, v in ipairs(rcs) do
        local g = rsm.compute_gradient(M, I, v.index)
        local leaving_index, max_change = rsm.find_leaving_variable(M, I, v.index, g)
        if max_change and math.abs(max_change) > I.TOLERANCE then
          if leaving_index < 0 then
            io.stderr:write(
              ("    After %d tries found ev %s: rc = %g, lv = ev, ev step = %g\n"):
              format(i, display_variable(M, I, v.index), I.reduced_costs[v.index], max_change))
          else
            io.stderr:write(
              ("    After %d tries found ev %s: rc = %g, lv %s: g = %g, ev step = %g\n"):
              format(i, display_variable(M, I, v.index), I.reduced_costs[v.index],
                     display_variable(M, I, I.basics[leaving_index]), g[leaving_index], max_change))
          end
          break
        end
      end
    end
  else
    io.stderr:write(("  Leaving variable is entering variable %s, change = %g\n"):format(display_variable(M, I, I.entering_index), I.max_change))
  end
end


local display_actions =
{
  iteration = display_iteration,
  entering_variable = display_entering_variable,
  leaving_variable = display_leaving_variable,
}


local function display(M, I, S, what)
  local f = display_actions[what:lower()]
  if f then f(M, I, S) end
end


-- Diagnosing problems ---------------------------------------------------------

local function diagnose_infeasibility(M, I, S)
  function display_infeasible()
    -- Find infeasible constraints
    local infeasible_constraints = {}
    for i = 1, M.nrows do
      if I.basics[i] > M.nvars and math.abs(I.x[I.basics[i]]) > I.TOLERANCE  then
        infeasible_constraints[#infeasible_constraints+1] = I.basics[i] - M.nvars
      end
    end

    -- And display them
    io.stderr:write("Infeasible Constraints:\n")
    for _, c in ipairs(infeasible_constraints) do
      display_constraint(M, I, c)
    end
  end

  io.stderr:write("\n\nINFEASIBLE\n")
  display_infeasible()
  while true do
    io.stderr:write("What now?\n * 'I' to display infeasible constraints\n * variable number or name to display constraints involving that variable\n * blank line to finish\n> ")
    local a = io.read("*l")
    if not a or #a == 0 then break end
    if a:lower() == "i" then
      display_infeasible()
    else
      local v
      local tna = tonumber(a)
      if tna and tna > 0 and tna <= M.nvars then
        v = tna
      elseif M.variable_names then
        for i, n in ipairs(M.variable_names) do
          if n:lower() == a:lower() then
            v = i
            break
          end
        end
      end
      if not v then
        io.stderr:write("I'm sorry, I didn't understand that variable name\n")
      else
        local related_constraints = {}
        for i = 1, M.nrows do
          local a = M.A[i]
          for _, v2 in ipairs(a.indexes) do
            if v == v2 then related_constraints[i] = true end
          end
        end
        local src = {}
        for c in pairs(related_constraints) do
          src[#src+1] = c
        end
        table.sort(src)

        io.stderr:write("Constraints containing ", a, ":\n")
        for _, c in ipairs(src) do
          display_constraint(M, I, c)
        end
      end
    end  
  end
end


local diagnose_actions =
{
  infeasible = diagnose_infeasibility,
  unbounded = diagnose_infeasibility,
  ["bound violation"] = diagnose_infeasibility,
  ["constraint violation"] = diagnose_infeasibility,
}


local function diagnose(M, I, S, what)
  local f = diagnose_actions[what:lower()]
  if f then f(M, I, S) end
end


--------------------------------------------------------------------------------

return { check = check, display = display, diagnose = diagnose }


-- EOF -------------------------------------------------------------------------

