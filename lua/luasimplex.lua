-- Utilities for the simplex method


-- RSM error -------------------------------------------------------------------

local rsm_exception = {}

function rsm_exception:new(error, M, I, S)
  local e = { error=error, M=M, I=I, S=S }
  self.__index = self
  return setmetatable(e, self)
end


function rsm_exception:__tostring()
  return self.error
end


local function rsm_error(e, M, I, S)
  error(rsm_exception:new(e, M, I, S), 2)
end


-- FFI-aware array construction ------------------------------------------------

local darray, iarray

local function array_init()
  if jit and jit.status and jit.status() then
    local ok, ffi = pcall(require, "ffi")
    if ok then
      local darrayi = ffi.typeof("double[?]")
      local iarrayi = ffi.typeof("int[?]")
      darray = function(n, ...) if select('#', ...) == 1 then return darrayi(n+1, select(1, ...)) else return darrayi(n+1, 0, ...) end end
      iarray = function(n, ...) if select('#', ...) == 1 then return iarrayi(n+1, select(1, ...)) else return iarrayi(n+1, 0, ...) end end
      return
    end
  end
  darray = function(n, ...)
    local a = {...}
    local l = select('#', ...)
    if l == 0 then
      for i = 1, n do a[i] = 0 end
    elseif l == 1 then
      local v = select(1, ...)
      for i = 2, n do a[i] = v end
    end
    return a
  end
  iarray = darray
end

array_init()


-- Allocating models and model instances ---------------------------------------

local function new_model(nrows, nvars, nonzeroes)
  M = {}

  M.nvars = nvars
  M.nrows = nrows
  M.nonzeroes = nonzeroes

  M.indexes = iarray(nonzeroes)
  M.row_starts = iarray(nrows+1)
  M.elements = darray(nonzeroes)

  M.b = darray(nrows)
  M.c = darray(nvars)
  M.xl = darray(nvars)
  M.xu = darray(nvars)

  return M
end


local function new_instance(nrows, nvars, use_c)
    I = {}

  local total_vars = nvars + nrows

  I.status = iarray(total_vars)
  I.basics = iarray(nrows)
  I.basic_cycles = iarray(nvars, 0)

  I.costs = darray(nvars, 0)
  I.x = darray(total_vars)
  I.xu = darray(total_vars)
  I.xl = darray(total_vars)

  I.basic_costs = darray(nrows)
  I.pi = darray(nrows, 0)
  I.reduced_costs = darray(nvars, 0)
  I.gradient = darray(nrows, 0)
  I.Binverse = darray(nrows * nrows)

  return I
end


--------------------------------------------------------------------------------

return
{
  error=rsm_error,
  iarray=iarray, darray=darray,
  new_model = new_model,
  new_instance = new_instance,
}


-- EOF -------------------------------------------------------------------------

