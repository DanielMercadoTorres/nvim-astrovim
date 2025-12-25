local M = {}
local api = vim.api

local enabled = true
local AUGROUP_NAME = "GitBlameVirtualText"

-- Namespace para virtual text
local blame_ns = api.nvim_create_namespace "git_blame_virtual_text"

-- Cache por línea para no llamar a git innecesariamente
local blame_cache = {}

-- Highlight groups estilo GitLens
vim.api.nvim_command "highlight GitBlameAuthor guifg=#A9B1D6 gui=bold"
vim.api.nvim_command "highlight GitBlameDate   guifg=#7AA2F7 gui=italic"
vim.api.nvim_command "highlight GitBlameMsg    guifg=#C0CAF5 gui=none"

-- Helper para generar clave de cache
local function cache_key(file, line) return file .. ":" .. line end

-- Función principal para mostrar blame virtual text
function M.blameVirtText()
  if not enabled then return end
  local ft = vim.fn.expand "%:h:t"
  if ft == "" or ft == "bin" then return end

  local mode = api.nvim_get_mode().mode
  if mode:match "i" then return end -- No mostrar en modo insert

  local currFile = vim.fn.expand "%:p"
  local line = api.nvim_win_get_cursor(0)[1]
  local key = cache_key(currFile, line)

  -- Limpiar solo la línea actual
  api.nvim_buf_clear_namespace(0, blame_ns, line - 1, line)

  -- Usar cache si existe
  if blame_cache[key] then
    api.nvim_buf_set_extmark(0, blame_ns, line - 1, 0, {
      virt_text = blame_cache[key],
      virt_text_pos = "eol",
      priority = 100,
    })
    return
  end

  -- Ejecutar git blame
  local blame = vim.fn.systemlist({
    "git",
    "blame",
    "-c",
    "-L",
    string.format("%d,%d", line, line),
    currFile,
  })[1] or ""

  if blame == "" then return end

  local hash = vim.split(blame, "%s")[1]
  local text

  if hash == "00000000" then
    text = "Not Committed Yet"
  else
    -- Obtener autor, fecha y mensaje
    local result = vim.fn.systemlist {
      "git",
      "show",
      hash,
      "--format=%an | %ar | %s",
    }

    text = result[1] or "Not Committed Yet"
    text = vim.split(text, "\n")[1]

    if text:find "fatal" then text = "Not Committed Yet" end
  end

  -- Separar autor, fecha y mensaje
  local author, date, msg = text:match "^(.-) | (.-) | (.*)$"
  if not author then
    author, date, msg = "?", "?", text
  end

  -- Crear virtual text con colores
  local virt_text = {
    { author .. " ", "GitBlameAuthor" },
    { date .. " ", "GitBlameDate" },
    { msg, "GitBlameMsg" },
  }

  -- Guardar en cache
  blame_cache[key] = virt_text

  -- Mostrar virtual text
  api.nvim_buf_set_extmark(0, blame_ns, line - 1, 0, {
    virt_text = virt_text,
    virt_text_pos = "eol",
    priority = 100,
  })
end

-- Función para limpiar virtual text
function M.clearBlameVirtText() api.nvim_buf_clear_namespace(0, blame_ns, 0, -1) end

-- Función para mostrar cache en ventana flotante
function M.showCachePopup()
  -- Crear un buffer temporal para la ventana flotante
  local buf = api.nvim_create_buf(false, true)

  -- Preparar líneas para mostrar: cada entrada de cache en formato "file:line = autor | fecha | mensaje"
  local lines = {}
  for key, virt_text in pairs(blame_cache) do
    -- virt_text es un arreglo de {texto, hl_group}
    -- Vamos a extraer solo el texto para mostrar concatenado
    local parts = {}
    for _, chunk in ipairs(virt_text) do
      table.insert(parts, chunk[1])
    end
    table.insert(lines, key .. " = " .. table.concat(parts, ""))
  end

  if #lines == 0 then lines = { "Cache vacía" } end

  -- Estilo ventana flotante
  local width = math.min(80, vim.o.columns - 4)
  local height = math.min(15, #lines)
  local opts = {
    style = "minimal",
    relative = "editor",
    width = width,
    height = height,
    row = (vim.o.lines - height) / 2 - 1,
    col = (vim.o.columns - width) / 2,
    border = "rounded",
  }

  -- Setear contenido en el buffer
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Crear la ventana flotante
  local win = api.nvim_open_win(buf, true, opts)

  -- Opcional: mapa para cerrar rápido la ventana con <Esc> o q
  api.nvim_buf_set_keymap(buf, "n", "q", "<Cmd>bd!<CR>", { nowait = true, noremap = true, silent = true })
  api.nvim_buf_set_keymap(buf, "n", "<Esc>", "<Cmd>bd!<CR>", { nowait = true, noremap = true, silent = true })
end

-- Configurar autocomandos
function M.setup_autocmds()
  local group = api.nvim_create_augroup(AUGROUP_NAME, { clear = true })

  -- Mostrar blame cuando el cursor está quieto
  api.nvim_create_autocmd("CursorHold", {
    group = group,
    callback = function()
      if vim.api.nvim_get_mode().mode:match "i" then return end
      M.blameVirtText()
    end,
  })

  -- Limpiar blame al mover el cursor
  api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = group,
    callback = function() M.clearBlameVirtText() end,
  })
end

function M.toggleBlame()
  enabled = not enabled

  if not enabled then
    M.clearBlameVirtText()
    api.nvim_del_augroup_by_name(AUGROUP_NAME)
    vim.notify("Git Blame disabled", vim.log.levels.INFO)
  else
    M.setup_autocmds()
    vim.notify("Git Blame enabled", vim.log.levels.INFO)
  end
end

-- Inicializar autocomandos
M.setup_autocmds()

-- Retornar configuración para AstroNvim
return {
  "AstroNvim/astrocore",
  opts = {
    mappings = {
      n = {
        ["<Leader>gBt"] = {
          desc = "Toggle Git Blame (GitLens style)",
          function() M.toggleBlame() end,
        },
        ["<Leader>gBc"] = {
          desc = "Git Blame",
          function() M.blameVirtText() end,
        },
        ["<Leader>gBC"] = {
          desc = "Mostrar cache Git Blame",
          function() M.showCachePopup() end,
        },
      },
    },
  },
}
