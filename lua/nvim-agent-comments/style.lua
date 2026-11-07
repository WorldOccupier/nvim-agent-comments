local M = {}

local STALE = { label = 'Stale comment', title_group = 'CommentBoxStale', border_group = 'CommentBoxStaleBorder' }
local HANDLED =
  { label = '✓ Comment', title_group = 'CommentBoxHandledTitle', border_group = 'CommentBoxHandledBorder' }
local OPEN = { label = 'Comment', title_group = 'CommentBoxTitle', border_group = 'CommentBoxActiveBorder' }

function M.handled(comment) return #(comment.replies or {}) > 0 end

-- A stale comment shows as stale even when it has replies, since its anchor needs attention first.
function M.box(comment, status)
  if status == 'stale' then return STALE end
  if M.handled(comment) then return HANDLED end
  return OPEN
end

return M
