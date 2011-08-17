

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


--------------------------------------------------------------------------------

return { error=rsm_error, iarray=iarray, darray=darray }


-- EOF -------------------------------------------------------------------------

