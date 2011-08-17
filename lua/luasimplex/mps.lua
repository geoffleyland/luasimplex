local io, math = require("io"), require("math")
local ipairs, pairs = ipairs, pairs
local tostring = tostring
local print = print
local tonumber = tonumber

local luasimplex = require("luasimplex")

local mps = {}
setfenv(1, mps)


--------------------------------------------------------------------------------

local sections =
{
  NAME = function(l, model)
      model.name = l:match("%s*(%S+)")
    end,
  ROWS = function(l, model)
      local type, name = l:match("%s*(%S+)%s+(%S+)")
      if type == "N" then
        model.objective_name = name
        model.objective = {}
      else
        local r = { name = name, index = #model.rows + 1, type = type, indexes = {}, values = {}, rhs = 0 }
        model.row_map[name] = r
        model.rows[r.index] = r
      end
    end,
  COLUMNS = function(l, model)
      local name
      name, l = l:match("%s*(%S+)%s*(.*)")
      local v = model.variable_map[name]
      if not v then
        v = { name = name, index = #model.variables + 1, coeff = 0, lower = 0, upper = math.huge }
        model.variable_map[name] = v
        model.variables[v.index] = v
      end

      while l:len() > 0 do
        local row, value
        row, value, l = l:match("%s*(%S+)%s+(%S+)%s*(.*)")
        value = tonumber(value)

        if row == model.objective_name then
          v.coeff = value
        else
          local r = model.row_map[row]
          local i = r.indexes
          local j = #i+1
          i[j] = v.index
          r.values[j] = value
        end
      end
    end,
  RHS = function(l, model)
      l = l:match("%s%s%s%s%S*%s*(.*)")
      while l:len() > 0 do
        local row, value
        row, value, l = l:match("%s*(%S+)%s+(%S+)%s*(.*)")
        if row ~= model.objective_name then
          model.row_map[row].rhs = tonumber(value)
        end
      end
    end,
  RANGES = function(l, model)
      local name
      name, l = l:match("%s*(%S+)%s*(.*)")
      while l:len() > 0 do
        local row, value
        row, value, l = l:match("%s*(%S+)%s+(%S+)%s*(.*)")
        model.row_map[row].range = tonumber(value)
      end
    end,
  BOUNDS = function(l, model)
      local type
      type, l = l:match("%s(%S%S)%s%S*%s*(.*)")
      while l:len() > 0 do
        local variable, value
        variable, value, l = l:match("%s*(%S+)%s*(%S*)%s*(.*)")
        if value and value:len() > 0 then
          value = tonumber(value)
        else
          value = nil
        end
        
        local v = model.variable_map[variable]
        if type == "LO" then
          v.lower = value
        elseif type == "UP" then
          v.upper = value
        elseif type == "FX" then
          v.lower, v.upper = value, value
        elseif type == "FR" then
          v.lower, v.upper = -math.huge, math.huge
        elseif type == "MI" then
          v.lower = -math.huge
        elseif type == "PL" then
          v.upper = math.huge
        elseif type == "BV" then
          v.lower, v.upper, v.integer = 0, 1, true
        elseif type == "LI" then
          v.lower, v.integer = value, true
        elseif type == "UI" then
          v.upper, v.integer = value, true
        else
          error("Don't understand bound type "..SC)
        end
      end
    end
}


function read(f)
  -- read file
  local model =
  {
    variables = {},
    variable_map = {},
    rows = {},
    row_map = {},
  }
  local reader
  for l in f:lines() do
    local r, remainder = l:match("^(%S+)%s*(.*)")
    if r then
      if r == "ENDATA" then
        break
      else
        reader = sections[r]
        l = remainder
      end
    end
    if l:len() > 0 then
      reader(l, model)
    end
  end

  -- add slacks
  for i = 1, #model.rows do
    r = model.rows[i]

    local rhs, upper, coeff = r.rhs, 0, 0
    if r.type == "L" then
      coeff = 1
      if r.range then
        upper = math.abs(r.range)
      else
        upper = math.huge
      end
    elseif r.type == "G" then
      if r.range then
        upper = math.abs(range)
        rhs = rhs - upper
        coeff = 1
      else
        upper = math.huge
        coeff = -1
      end
    else -- type == "E"
      if r.range then
        coeff = 1
        upper = math.abs(r.range)
        if r.range < 0 then
          r.rhs = r.rhs - upper
        end
      end
    end
    r.rhs = rhs

    if coeff ~= 0 and upper > 0 then
      local name = r.name.."_SLACK"
      local v = { name = name, index = #model.variables + 1, coeff = 0, lower = 0, upper = upper }
      model.variable_map[name] = v
      model.variables[v.index] = v
      local j = #r.indexes+1
      r.indexes[j] = v.index
      r.values[j] = coeff
    end
  end


  local nvars, nrows = #model.variables, #model.rows
  local M =
  {
    name = model.name,
    variable_names = {},
    constraint_names = {},
    nvars = nvars,
    nrows = nrows,
    A = {},
    b = luasimplex.darray(nrows),
    c = luasimplex.darray(nvars),
    xl = luasimplex.darray(nvars),
    xu = luasimplex.darray(nvars),
  }

  -- Add constraints to model
  local nonzeroes = 0
  for i, r in ipairs(model.rows) do
    M.constraint_names[i] = r.name
    M.b[i] = r.rhs
    local elements = #r.indexes
    local a = { name = r.name, elements = elements, indexes = luasimplex.iarray(elements), values = luasimplex.darray(elements) }
    for j = 1, elements do
      a.indexes[j] = r.indexes[j]
      a.values[j] = r.values[j]
      nonzeroes = nonzeroes + 1
    end
    M.A[i] = a
  end
  M.nonzeroes = nonzeroes

  -- Add variables to model
  for i, v in ipairs(model.variables) do
    M.variable_names[i] = v.name
    M.c[i] = v.coeff
    M.xl[i] = v.lower
    M.xu[i] = v.upper
  end

  return M
end


function write(M)
  io.stderr:write("Variables:\n")
  for i = 1, M.nvars do
    io.stderr:write("  ", tostring(i), ": ", M.variable_names[i], " ", tostring(M.c[i]), " ", tostring(M.xl[i]), " ", tostring(M.xu[i]), "\n")
  end
  io.stderr:write("\nRows:\n")
  for i = 1, M.nrows do
    io.stderr:write("  ", tostring(i), ": ", M.constraint_names[i], " ", tostring(M.b[i]), ": ")
    for j = 1, M.A[i].elements do
      io.stderr:write(M.variable_names[M.A[i].indexes[j] ], ":", tostring(M.A[i].values[j]), " ")
    end
    io.stderr:write("\n")
  end

  io.stderr:write("\n\n")
end


--------------------------------------------------------------------------------

return mps


-- EOF -------------------------------------------------------------------------

