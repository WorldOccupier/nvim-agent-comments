vim.opt.rtp:prepend(vim.fn.getcwd())

local text_layout = require('nvim-agent-comments.text')

local function check_wrap(text, width, expected, message)
  local actual = text_layout.wrap(text, width)
  assert(vim.deep_equal(actual, expected), ('%s: got %s'):format(message, vim.inspect(actual)))
end

check_wrap('the quick brown fox jumps', 10, { 'the quick', 'brown fox', 'jumps' }, 'words did not wrap at spaces')
check_wrap('abcd efgh', 9, { 'abcd efgh' }, 'exact fit was wrapped')
check_wrap('abcd efgh', 8, { 'abcd', 'efgh' }, 'one column too narrow did not wrap')
check_wrap('go abcdefghij ok', 4, { 'go', 'abcd', 'efgh', 'ij', 'ok' }, 'long word was not hard broken')
check_wrap('a   b\t\tc', 10, { 'a b c' }, 'whitespace runs were not collapsed')
check_wrap('first\n\n  second  ', 20, { 'first', 'second' }, 'line breaks were not kept or blank lines remained')
check_wrap('', 10, {}, 'empty text produced lines')
check_wrap('  \n\t ', 10, {}, 'whitespace-only text produced lines')
check_wrap('日本語 です', 6, { '日本語', 'です' }, 'wide characters did not wrap by display width')
check_wrap('日本語', 4, { '日本', '語' }, 'wide word was not broken by display width')
check_wrap('日本', 1, { '日', '本' }, 'width narrower than a character did not make progress')
check_wrap('ab c', 1, { 'a', 'b', 'c' }, 'width 1 did not break every character')
check_wrap('ab', 0, { 'a', 'b' }, 'width 0 did not make progress')

check_wrap('e\204\129e\204\129', 1, { 'e\204\129', 'e\204\129' }, 'composing character was split from its base')
assert(text_layout.truncate_display('日本語', 5) == '日本', 'truncate did not respect display width')

local hrtime = (vim.uv or vim.loop).hrtime
local started = hrtime()
local long_word_lines = text_layout.wrap(string.rep('a', 20000), 75)
local elapsed_seconds = (hrtime() - started) / 1e9
assert(#long_word_lines == math.ceil(20000 / 75), 'long word was not broken into full-width pieces')
assert(elapsed_seconds < 0.5, ('wrapping a long word took %.2f s'):format(elapsed_seconds))

print('nvim-agent-comments text tests passed')
vim.cmd('qa!')
