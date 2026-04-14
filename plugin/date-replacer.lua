if vim.g.loaded_date_replacer == 1 then
  return
end

vim.g.loaded_date_replacer = 1

require('date-formatter').setup()
