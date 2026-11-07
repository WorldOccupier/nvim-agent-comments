local M = {}

local MIN_WIDTH = 1

-- Splitting on \zs keeps composing characters attached to their base character.
local function characters(text) return vim.fn.split(text, [[\zs]]) end

function M.truncate_display(text, width)
  local used, length = 0, 0
  for _, character in ipairs(characters(text)) do
    used = used + vim.fn.strdisplaywidth(character)
    if used > width then break end
    length = length + #character
  end
  return text:sub(1, length)
end

-- Each piece takes at least one character so a character wider than the width still makes progress.
local function split_word(word, width)
  local pieces, piece, used = {}, {}, 0
  for _, character in ipairs(characters(word)) do
    local character_width = vim.fn.strdisplaywidth(character)
    if used + character_width > width and #piece > 0 then
      pieces[#pieces + 1] = table.concat(piece)
      piece, used = {}, 0
    end
    piece[#piece + 1] = character
    used = used + character_width
  end
  pieces[#pieces + 1] = table.concat(piece)
  return pieces
end

local function wrap_paragraph(paragraph, width, lines)
  local current = ''
  for word in paragraph:gmatch('%S+') do
    local candidate = current == '' and word or current .. ' ' .. word
    if vim.fn.strdisplaywidth(candidate) <= width then
      current = candidate
    else
      if current ~= '' then lines[#lines + 1] = current end
      local pieces = split_word(word, width)
      for index = 1, #pieces - 1 do
        lines[#lines + 1] = pieces[index]
      end
      current = pieces[#pieces]
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
