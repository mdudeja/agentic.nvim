--- Structured error for Agentic RPC calls.
---
--- The server always answers `{ result, error }` where `success: false` may be
--- carried inside `result` as well as a populated `error.message`. Callers that
--- only care about "did it work" use `:ok()`, others read `message` for display.
---@class Agentic.rpc.Error
---@field message string
---@field code number?
---@field method string?
local Error = {}
Error.__index = Error

---@param message string
---@param opts? { code: number?, method: string? }
---@return Agentic.rpc.Error
function Error.new(message, opts)
  return setmetatable({
    message = message,
    code = opts and opts.code,
    method = opts and opts.method,
  }, Error)
end

function Error:__tostring()
  if self.method then
    return string.format("[%s] %s", self.method, self.message)
  end
  return self.message
end

return Error
