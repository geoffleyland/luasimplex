local io, math = require("io"), require("math")
local error, ipairs, pairs, tonumber, tostring, type =
      error, ipairs, pairs, tonumber, tostring, type

local luasimplex = require("luasimplex")


--------------------------------------------------------------------------------

local sections =
{
  NAME = function(l, model)
      model.name = l:match("%s*(%S+)")
    end,
  OBJECT = function(l, model)
    -- I can't find any documentation for OBJECT lines, so I'll ignore them.
    end,
  ROWS = function(l, model)
      local type, name = l:match("%s*(%S+)%s+(.*)")
      name = name:gsub("%s+$", "")
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
      name, l = l:match("%s*(........)%s*(.*)")
      name = name:gsub("%s+$", "")
      local v = model.variable_map[name]
      if not v then
        v = { name = name, index = #model.variables + 1, coeff = 0, lower = 0, upper = math.huge }
        model.variable_map[name] = v
        model.variables[v.index] = v
      end

      while #l > 0 do
        local row, value
        row, value, l = l:match("%s*(........)%s+(%S+)%s*(.*)")
        row = row:gsub("%s+$", "")
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
      l = l:match("%s%s%s%s........%s+(.*)")
      while #l > 0 do
        local row, value
        row, value, l = l:match("%s*(........)%s+(%S+)%s*(.*)")
        row = row:gsub("%s+$", "")
        if row ~= model.objective_name then
          model.row_map[row].rhs = tonumber(value)
        end
      end
    end,
  RANGES = function(l, model)
      l = l:match("%s%s%s%s........%s+(.*)")
      while #l > 0 do
        local row, value
        row, value, l = l:match("%s*(%S+)%s+(%S+)%s*(.*)")
        model.row_map[row].range = tonumber(value)
      end
    end,
  BOUNDS = function(l, model)
      local type
      type, l = l:match("%s(%S%S)%s........%s*(.*)")
      while #l > 0 do
        local variable, value
        variable, value, l = l:match("%s*(..?.?.?.?.?.?.?)%s*(%S*)%s*(.*)")
        variable = variable:gsub("%s+$", "")
        if value and #value > 0 then
          value = tonumber(value)
        else
          value = nil
        end
        
        local v = model.variable_map[variable]
        if not v then
          error("Unknown variable '"..variable.."'")
        end
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


local function read(f, c_structs, c_arrays)
  c_structs = c_structs or false
  local offset = c_arrays and -1 or 0

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
    if not l:match("^%*") then
      local r, remainder = l:match("^(%S+)%s*(.*)")
      if r then
        if r == "ENDATA" then
          break
        else
          reader = sections[r]
          if not reader then
            error("Unkown section '"..r.."'")
          end
          l = remainder
        end
      end
      if #l > 0 then
        reader(l, model)
      end
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
        upper = math.abs(r.range)
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

  local nonzeroes = 0
  for i, r in ipairs(model.rows) do
    nonzeroes = nonzeroes + #r.indexes
  end

  local M = luasimplex.new_model(nrows, nvars, nonzeroes, c_structs)

  if type(M) == "table" then
    M.name = model.name
    M.variable_names = {}
    M.constraint_names = {}
  end

  -- Add constraints to model
  local element_index = 1
  for i, r in ipairs(model.rows) do
    if type(M) == "table" then
    M.constraint_names[i] = r.name
    end
    M.b[i+offset] = r.rhs
    M.row_starts[i+offset] = element_index+offset
    for j = 1, #r.indexes do
      M.indexes[element_index+offset] = r.indexes[j]+offset
      M.elements[element_index+offset] = r.values[j]
      element_index = element_index + 1
    end
  end
  M.row_starts[nrows+1+offset] = nonzeroes+1+offset

  -- Add variables to model
  for i, v in ipairs(model.variables) do
    if type(M) == "table" then
    M.variable_names[i] = v.name
    end
    M.c[i+offset] = v.coeff
    M.xl[i+offset] = v.lower
    M.xu[i+offset] = v.upper
  end

  return M
end


local function write(M)
  local variable_names = type(M) == "table" and M.variable_names
  local constraint_names = type(M) == "table" and M.constraint_names
  io.stderr:write("Variables:\n")
  for i = 1, M.nvars do
    io.stderr:write("  ", tostring(i), ": ", variable_names and variable_names[i] or "", " ", tostring(M.c[i]), " ", tostring(M.xl[i]), " ", tostring(M.xu[i]), "\n")
  end
  io.stderr:write("\nRows:\n")
  for i = 1, M.nrows do
    io.stderr:write("  ", tostring(i), ": ", constraint_names and constraint_names[i] or "", " ", tostring(M.b[i]), ": ")
    for j = M.row_starts[i], M.row_starts[i+1]-1 do
      io.stderr:write(variable_names and variable_names[M.indexes[j] ] or tostring(M.indexes[j]), ":", tostring(M.elements[j]), " ")
    end
    io.stderr:write("\n")
  end

  io.stderr:write("\n\n")
end


--------------------------------------------------------------------------------

return { read = read, write = write }


-- EOF -------------------------------------------------------------------------

