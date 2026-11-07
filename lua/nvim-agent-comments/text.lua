local M = {}

local MIN_WIDTH = 1

function M.truncate_display(text, width)
  local length = vim.fn.strchars(text)
  while length > 0 and vim.fn.strdisplaywidth(vim.fn.strcharpart(text, 0, length)) > width do
    length = length - 1
  end
  return vim.fn.strcharpart(text, 0, length)
end

-- Takes at least one character so a character wider than the width still makes progress.
local function split_word(word, width)
  local head = M.truncate_display(word, width)
  if head == '' then head = vim.fn.strcharpart(word, 0, 1) end
  return head, word:sub(#head + 1)
end

local function wrap_paragraph(paragraph, width, lines)
  local current = ''
  for word in paragraph:gmatch('%S+') do
    local candidate = current == '' and word or current .. ' ' .. word
    if vim.fn.strdisplaywidth(candidate) <= width then
      current = candidate
    else
      if current ~= '' then lines[#lines + 1] = current end
      while vim.fn.strdisplaywidth(word) > width do
        local head
        head, word = split_word(word, width)
        lines[#lines + 1] = head
      end
      current = word
    end
  end
  if current ~= '' then lines[#lines + 1] = current end
end

-- Line breaks in the text are kept; other whitespace runs collapse to one space and blank lines are dropped.
function M.wrap(text, width)
  width = math.max(MIN_WIDTH, width)
  local lines = {}
  for paragraph in (text .. '\n'):gmatch('([^\n]*)\n') do
    wrap_paragraph(paragraph, width, lines)
  end
  return lines
end

return M
