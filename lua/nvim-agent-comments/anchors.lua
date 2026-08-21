local M = {}

local DEFAULT_CONTEXT_LINES = 2
local FIRST_LINE = 1
local NO_MATCHES = 0

local function slice(lines, start_line, end_line)
  local result = {}
  for line = start_line, end_line do
    result[#result + 1] = lines[line]
  end
  return result
end

local function equal_lines(lines, start_line, context)
  for offset, expected in ipairs(context) do
    if lines[start_line + offset - 1] ~= expected then
      return false
    end
  end
  return true
end

function M.capture(lines, start_line, end_line, context_lines)
  context_lines = context_lines or DEFAULT_CONTEXT_LINES
  local context_start = math.max(FIRST_LINE, start_line - context_lines)
  local context_end = math.min(#lines, end_line + context_lines)

  return {
    context = slice(lines, context_start, context_end),
    context_start_offset = start_line - context_start,
  }
end

function M.resolve(lines, comment)
  local context = comment.context or {}
  if #context == NO_MATCHES then
    return { status = 'stale', reason = 'comment has no context' }
  end

  local matches = {}
  for start_line = FIRST_LINE, #lines - #context + FIRST_LINE do
    if equal_lines(lines, start_line, context) then
      matches[#matches + 1] = start_line
    end
  end

  if #matches ~= 1 then
    return {
      status = 'stale',
      reason = #matches == NO_MATCHES and 'comment context was not found' or 'comment context is ambiguous',
    }
  end

  local target_start = matches[FIRST_LINE] + (comment.context_start_offset or 0)
  local target_length = comment.end_line - comment.start_line
  return {
    status = 'resolved',
    start_line = target_start,
    end_line = target_start + target_length,
  }
end

return M
