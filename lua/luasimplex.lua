-- Utilities for the simplex method


local luasimplex = {}

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


function luasimplex.error(e, M, I, S)
  error(rsm_exception:new(e, M, I, S), 2)
end


-- FFI-aware array construction ------------------------------------------------

local ok, ffi = pcall(require, "ffi")
if not ok then ffi = nil end

function luasimplex.array_init(no_ffi)
  if ffi and not no_ffi then
      local darrayi = ffi.typeof("double[?]")
      local iarrayi = ffi.typeof("int[?]")
    luasimplex.darray = function(n, ...) if select('#', ...) == 1 then return darrayi(n+1, select(1, ...)) else return darrayi(n+1, 0, ...) end end
    luasimplex.iarray = function(n, ...) if select('#', ...) == 1 then return iarrayi(n+1, select(1, ...)) else return iarrayi(n+1, 0, ...) end end
  else
    luasimplex.darray = function(n, ...)
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
    luasimplex.iarray = luasimplex.darray
end
end

luasimplex.array_init()


-- Allocating models and model instances ---------------------------------------

if ffi then
  local header = io.open("../c/rsm.h", "r")
  if header then
    if pcall(ffi.cdef, header:read("*a")) then
      header:close()
      local ok
      ok, luasimplex.crsm = pcall(ffi.load, "rsm")
      if not ok then luasimplex.crsm = nil end
    end
  end
end

if luasimplex.crsm then print("C RSM is available") end

function luasimplex.new_model(nrows, nvars, nonzeroes, use_c)
  local M
  if use_c and luasimplex.crsm then
    M = ffi.new("model")
    luasimplex.crsm.new_model(M, nrows, nvars, nonzeroes)
  else
    M = {}

    M.nvars = nvars
    M.nrows = nrows
    M.nonzeroes = nonzeroes

    M.indexes = luasimplex.iarray(nonzeroes)
    M.row_starts = luasimplex.iarray(nrows+1)
    M.elements = luasimplex.darray(nonzeroes)

    M.b = luasimplex.darray(nrows)
    M.c = luasimplex.darray(nvars)
    M.xl = luasimplex.darray(nvars)
    M.xu = luasimplex.darray(nvars)
  end
  return M
end


function luasimplex.free_model(M)
  if type(M) ~= "table" then
    luasimplex.crsm.free_model(M)
  end
end


function luasimplex.new_instance(nrows, nvars, use_c)
  local I
  if use_c and luasimplex.crsm then
    I = ffi.new("instance")
    luasimplex.crsm.new_instance(I, nrows, nvars)
  else
    I = {}

    local total_vars = nvars + nrows

    I.status = luasimplex.iarray(total_vars)
    I.basics = luasimplex.iarray(nrows)
    I.basic_cycles = luasimplex.iarray(nvars, 0)

    I.costs = luasimplex.darray(nvars, 0)
    I.x = luasimplex.darray(total_vars)
    I.xu = luasimplex.darray(total_vars)
    I.xl = luasimplex.darray(total_vars)

    I.basic_costs = luasimplex.darray(nrows)
    I.pi = luasimplex.darray(nrows, 0)
    I.reduced_costs = luasimplex.darray(nvars, 0)
    I.gradient = luasimplex.darray(nrows, 0)
    I.Binverse = luasimplex.darray(nrows * nrows)
  end
  return I
end


function luasimplex.free_instance(I)
  if type(I) ~= "table" then
    luasimplex.crsm.free_instance(I)
  end
end


--------------------------------------------------------------------------------

return luasimplex


-- EOF -------------------------------------------------------------------------

