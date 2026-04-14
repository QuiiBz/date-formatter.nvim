local M = {}

local MONTH_NAMES = {
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
}

local DEFAULT_OPTIONS = {
  auto = false,
  events = { 'BufEnter', 'TextChanged', 'TextChangedI', 'InsertLeave' },
  filetypes = nil,
  buftypes = nil,
}

local NAMESPACE = vim.api.nvim_create_namespace('date-formatter')

local state = {
  options = vim.deepcopy(DEFAULT_OPTIONS),
  command_created = false,
  processing = {},
}

local REPLACERS = {
  {
    pattern = '%f[%d](%d%d%d%d)%-(%d%d)%-(%d%d)[Tt ](%d%d):(%d%d):(%d%d)%f[^%d]',
    has_time = true,
    has_seconds = true,
  },
  {
    pattern = '%f[%d](%d%d%d%d)%/(%d%d)%/(%d%d)[Tt ](%d%d):(%d%d):(%d%d)%f[^%d]',
    has_time = true,
    has_seconds = true,
  },
  {
    pattern = '%f[%d](%d%d%d%d)%-(%d%d)%-(%d%d)[Tt ](%d%d):(%d%d)%f[^%d]',
    has_time = true,
    has_seconds = false,
  },
  {
    pattern = '%f[%d](%d%d%d%d)%/(%d%d)%/(%d%d)[Tt ](%d%d):(%d%d)%f[^%d]',
    has_time = true,
    has_seconds = false,
  },
  {
    pattern = '%f[%d](%d%d%d%d)%-(%d%d)%-(%d%d)%f[^%d]',
    has_time = false,
  },
  {
    pattern = '%f[%d](%d%d%d%d)%/(%d%d)%/(%d%d)%f[^%d]',
    has_time = false,
  },
}

local function contains(values, needle)
  if values == nil then
    return true
  end

  for _, value in ipairs(values) do
    if value == needle then
      return true
    end
  end

  return false
end

local function is_buffer_enabled(bufnr)
  local value = vim.b[bufnr].date_replacer_enabled
  if value == nil then
    return state.options.auto
  end

  return value == true
end

local function set_buffer_enabled(bufnr, enabled)
  vim.b[bufnr].date_replacer_enabled = enabled and true or false
end

local function clear_annotations(bufnr, start_line, end_line)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, NAMESPACE, start_line or 0, end_line or -1)
  end
end

local function pluralize(unit, value)
  if value == 1 then
    return unit
  end
  return unit .. 's'
end

local function format_relative_time(timestamp, now)
  local delta = now - timestamp
  local abs_delta = math.abs(delta)

  if abs_delta < 5 then
    return 'just now'
  end

  local units = {
    { name = 'year', seconds = 31536000 },
    { name = 'month', seconds = 2592000 },
    { name = 'week', seconds = 604800 },
    { name = 'day', seconds = 86400 },
    { name = 'hour', seconds = 3600 },
    { name = 'minute', seconds = 60 },
    { name = 'second', seconds = 1 },
  }

  for _, unit in ipairs(units) do
    local value = math.floor(abs_delta / unit.seconds)
    if value >= 1 then
      local formatted = string.format('%d %s', value, pluralize(unit.name, value))
      if delta >= 0 then
        return formatted .. ' ago'
      end
      return 'in ' .. formatted
    end
  end

  return 'just now'
end

local function normalize_parts(year, month, day, hour, min, sec)
  local parsed_year = tonumber(year)
  local parsed_month = tonumber(month)
  local parsed_day = tonumber(day)
  local parsed_hour = tonumber(hour) or 0
  local parsed_min = tonumber(min) or 0
  local parsed_sec = tonumber(sec) or 0

  if parsed_year == nil or parsed_month == nil or parsed_day == nil then
    return nil
  end

  if parsed_month < 1 or parsed_month > 12 then
    return nil
  end

  if parsed_day < 1 or parsed_day > 31 then
    return nil
  end

  if parsed_hour < 0 or parsed_hour > 23 then
    return nil
  end

  if parsed_min < 0 or parsed_min > 59 then
    return nil
  end

  if parsed_sec < 0 or parsed_sec > 59 then
    return nil
  end

  local timestamp = os.time({
    year = parsed_year,
    month = parsed_month,
    day = parsed_day,
    hour = parsed_hour,
    min = parsed_min,
    sec = parsed_sec,
  })

  if timestamp == nil then
    return nil
  end

  local normalized = os.date('*t', timestamp)
  if normalized.year ~= parsed_year or normalized.month ~= parsed_month or normalized.day ~= parsed_day then
    return nil
  end

  if normalized.hour ~= parsed_hour or normalized.min ~= parsed_min or normalized.sec ~= parsed_sec then
    return nil
  end

  return timestamp
end

local function format_absolute_time(timestamp, has_time)
  local parts = os.date('*t', timestamp)
  if has_time then
    return string.format(
      '%s %d %04d, %02d:%02d',
      MONTH_NAMES[parts.month],
      parts.day,
      parts.year,
      parts.hour,
      parts.min
    )
  end

  return string.format('%s %d %04d', MONTH_NAMES[parts.month], parts.day, parts.year)
end

local function build_replacement(timestamp, has_time, now)
  local absolute = format_absolute_time(timestamp, has_time)
  local relative = format_relative_time(timestamp, now)
  return string.format('%s (%s)', absolute, relative)
end

local function build_annotation_text(replacer, now, c1, c2, c3, c4, c5, c6)
  local timestamp

  if replacer.has_time then
    if replacer.has_seconds then
      timestamp = normalize_parts(c1, c2, c3, c4, c5, c6)
    else
      timestamp = normalize_parts(c1, c2, c3, c4, c5, 0)
    end
  else
    timestamp = normalize_parts(c1, c2, c3, 0, 0, 0)
  end

  if timestamp == nil then
    return nil
  end

  return build_replacement(timestamp, replacer.has_time, now)
end

local function overlaps_existing(matches, start_idx, end_idx)
  for _, existing in ipairs(matches) do
    if not (end_idx < existing.start_idx or start_idx > existing.end_idx) then
      return true
    end
  end

  return false
end

local function find_matches_in_line(line, now)
  local matches = {}

  for _, replacer in ipairs(REPLACERS) do
    local search_start = 1

    while search_start <= #line do
      local start_idx, end_idx, c1, c2, c3, c4, c5, c6 = line:find(replacer.pattern, search_start)
      if start_idx == nil then
        break
      end

      if not overlaps_existing(matches, start_idx, end_idx) then
        local annotation = build_annotation_text(replacer, now, c1, c2, c3, c4, c5, c6)
        if annotation ~= nil then
          table.insert(matches, {
            start_idx = start_idx,
            end_idx = end_idx,
            text = annotation,
          })
        end
      end

      search_start = end_idx + 1
    end
  end

  table.sort(matches, function(left, right)
    return left.start_idx < right.start_idx
  end)

  return matches
end

local function can_process_buffer(bufnr, opts)
  opts = opts or {}

  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  local filetype = vim.bo[bufnr].filetype
  local buftype = vim.bo[bufnr].buftype

  if buftype == 'terminal' then
    return false
  end

  if not opts.ignore_toggle and not is_buffer_enabled(bufnr) then
    return false
  end

  if not contains(state.options.filetypes, filetype) then
    return false
  end

  if not contains(state.options.buftypes, buftype) then
    return false
  end

  return true
end

--- Render date annotations in a buffer range.
--- @param opts {bufnr?:integer, start_line?:integer, end_line?:integer, now?:integer, force?:boolean}|nil
--- @return {changed:boolean,replacements:integer}
function M.replace_dates_in_buffer(opts)
  opts = opts or {}

  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count == 0 then
    return { changed = false, replacements = 0 }
  end

  local start_line = opts.start_line or 0
  local end_line = opts.end_line

  if end_line == nil then
    end_line = line_count
  end

  if start_line < 0 then
    start_line = 0
  end

  if end_line > line_count then
    end_line = line_count
  end

  if end_line <= start_line then
    return { changed = false, replacements = 0 }
  end

  if not can_process_buffer(bufnr, { ignore_toggle = opts.force == true }) then
    return { changed = false, replacements = 0 }
  end

  clear_annotations(bufnr, start_line, end_line)

  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line, end_line, false)
  local now = opts.now or os.time()
  local replacements = 0

  for row_offset, line in ipairs(lines) do
    local row = start_line + row_offset - 1
    local matches = find_matches_in_line(line, now)

    for _, match in ipairs(matches) do
      vim.api.nvim_buf_set_extmark(bufnr, NAMESPACE, row, match.end_idx, {
        virt_text = { { ' (' .. match.text .. ')', 'Comment' } },
        virt_text_pos = 'inline',
        hl_mode = 'combine',
      })
      replacements = replacements + 1
    end
  end

  return {
    changed = replacements > 0,
    replacements = replacements,
  }
end

local function create_command()
  if state.command_created then
    return
  end

  local function refresh_visible(bufnr)
    local result = M.refresh_visible_in_buffer({
      bufnr = bufnr,
    })

    return result
  end

  vim.api.nvim_create_user_command('DateReplacer', function()
    local bufnr = vim.api.nvim_get_current_buf()

    if not can_process_buffer(bufnr, { ignore_toggle = true }) then
      vim.notify('DateReplacer: current buffer is not eligible for replacement', vim.log.levels.INFO)
      return
    end

    local next_state = not is_buffer_enabled(bufnr)
    set_buffer_enabled(bufnr, next_state)

    if not next_state then
      clear_annotations(bufnr, 0, -1)
      vim.notify('DateReplacer: disabled for current buffer', vim.log.levels.INFO)
      return
    end

    local result = refresh_visible(bufnr)
    if result.replacements == 0 then
      vim.notify('DateReplacer: enabled for current buffer (no date-like values found)', vim.log.levels.INFO)
      return
    end

    local suffix = result.replacements == 1 and '' or 's'
    vim.notify(
      string.format('DateReplacer: enabled for current buffer, showing %d date%s', result.replacements, suffix),
      vim.log.levels.INFO
    )
  end, {
    desc = 'Toggle DateReplacer for current buffer',
  })

  state.command_created = true
end

local function merge_ranges(ranges)
  if #ranges <= 1 then
    return ranges
  end

  table.sort(ranges, function(left, right)
    return left.start_line < right.start_line
  end)

  local merged = { ranges[1] }

  for index = 2, #ranges do
    local current = ranges[index]
    local last = merged[#merged]

    if current.start_line <= last.end_line then
      if current.end_line > last.end_line then
        last.end_line = current.end_line
      end
    else
      table.insert(merged, current)
    end
  end

  return merged
end

local function get_visible_ranges(bufnr)
  local ranges = {}
  local wins = vim.fn.win_findbuf(bufnr)

  for _, winid in ipairs(wins) do
    if vim.api.nvim_win_is_valid(winid) then
      local top = vim.fn.line('w0', winid) - 1
      local bottom = vim.fn.line('w$', winid)

      if top < 0 then
        top = 0
      end

      if bottom < top + 1 then
        bottom = top + 1
      end

      table.insert(ranges, {
        start_line = top,
        end_line = bottom,
      })
    end
  end

  return merge_ranges(ranges)
end

--- Refresh date annotations for only visible lines in all windows showing this buffer.
--- @param opts {bufnr?:integer, now?:integer}|nil
--- @return {changed:boolean,replacements:integer}
function M.refresh_visible_in_buffer(opts)
  opts = opts or {}

  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  if not can_process_buffer(bufnr) then
    return { changed = false, replacements = 0 }
  end

  local ranges = get_visible_ranges(bufnr)
  if #ranges == 0 then
    return { changed = false, replacements = 0 }
  end

  local replacements = 0
  local changed = false
  local now = opts.now or os.time()

  for _, range in ipairs(ranges) do
    local result = M.replace_dates_in_buffer({
      bufnr = bufnr,
      start_line = range.start_line,
      end_line = range.end_line,
      now = now,
    })

    if result.changed then
      changed = true
    end
    replacements = replacements + result.replacements
  end

  return {
    changed = changed,
    replacements = replacements,
  }
end

local function resolve_refresh_range(bufnr, event_name)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count == 0 then
    return 0, 0
  end

  if event_name == 'TextChanged' or event_name == 'TextChangedI' then
    if bufnr == vim.api.nvim_get_current_buf() then
      local row = vim.api.nvim_win_get_cursor(0)[1] - 1
      if row < 0 then
        row = 0
      end

      if row >= line_count then
        row = line_count - 1
      end

      return row, row + 1
    end
  end

  return 0, line_count
end

local function configure_autocmd()
  local group = vim.api.nvim_create_augroup('date-formatter', { clear = true })

  vim.api.nvim_create_autocmd(state.options.events, {
    group = group,
    callback = function(event)
      local bufnr = event.buf

      if state.processing[bufnr] then
        return
      end

      state.processing[bufnr] = true
      local ok, err

      if event.event == 'TextChanged' or event.event == 'TextChangedI' then
        local start_line, end_line = resolve_refresh_range(bufnr, event.event)
        ok, err = pcall(M.replace_dates_in_buffer, {
          bufnr = bufnr,
          start_line = start_line,
          end_line = end_line,
        })
      else
        ok, err = pcall(M.refresh_visible_in_buffer, {
          bufnr = bufnr,
        })
      end

      state.processing[bufnr] = nil

      if not ok then
        vim.schedule(function()
          vim.notify('DateReplacer: ' .. tostring(err), vim.log.levels.WARN)
        end)
      end
    end,
  })
end

--- Setup DateReplacer.
--- @param opts {auto?:boolean,events?:string[],filetypes?:string[]|nil,buftypes?:string[]|nil}|nil
function M.setup(opts)
  state.options = vim.tbl_deep_extend('force', vim.deepcopy(DEFAULT_OPTIONS), opts or {})

  create_command()
  configure_autocmd()
end

return M
