# date-formatter.nvim

**Vibecoded slop warning.**

Toggle inline date annotations for the current buffer.

The plugin keeps the original date text untouched and shows a readable value after it, so the raw date is still visible in Insert mode.

Example:

```text
Input:  4a5f649b Tom Lienard (2024-02-28 18:32):
View:   4a5f649b Tom Lienard (2024-02-28 18:32) (Feb 28 2024, 18:32 (2 years ago)):
```

## Features

- Non-destructive: your buffer content is not rewritten.
- `:DateReplacer` toggles annotations on/off for the current buffer.
- Incremental refresh: on text changes, only the edited line is recomputed.
- Full refresh is viewport-only: only visible lines are recomputed.
- Detects common date formats:
  - `YYYY-MM-DD`
  - `YYYY-MM-DD HH:MM`
  - `YYYY-MM-DD HH:MM:SS`
  - Same formats with `/` and `T`
- Shows:
  - absolute date (`Feb 28 2024, 18:32`)
  - relative age (`2 years ago`)

## Installation (lazy.nvim)

```lua
{
  'QuiiBz/date-formatter.nvim',
  opts = {
    auto = false,
  },
}
```

## Usage

- `:DateReplacer` to toggle date annotations for the current buffer.

## Configuration

```lua
require('date-formatter').setup({
  auto = false,
  events = { 'BufEnter', 'TextChanged', 'TextChangedI', 'InsertLeave' },
  filetypes = nil,
  buftypes = nil,
})
```

Options:

- `auto` (`boolean`): default enabled state for new buffers.
- `events` (`string[]`): autocmd events that refresh annotations.
- `filetypes` (`string[]|nil`): allow-list of filetypes, or `nil` for all.
- `buftypes` (`string[]|nil`): allow-list of buftypes, or `nil` for all.

## License

MIT
