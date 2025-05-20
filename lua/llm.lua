local M = {}
local Job = require 'plenary.job'

local function get_api_key(name)
  local key = os.getenv(name)
  if not key or key == "" then
    vim.notify("API key not found: " .. name, vim.log.levels.ERROR)
    return nil
  end
  return key
end

function M.get_lines_until_cursor()
  local current_buffer = vim.api.nvim_get_current_buf()
  local current_window = vim.api.nvim_get_current_win()
  local cursor_position = vim.api.nvim_win_get_cursor(current_window)
  local row = cursor_position[1]

  local lines = vim.api.nvim_buf_get_lines(current_buffer, 0, row, true)

  return table.concat(lines, '\n')
end

function M.get_visual_selection()
  local _, srow, scol = unpack(vim.fn.getpos 'v')
  local _, erow, ecol = unpack(vim.fn.getpos '.')

  if vim.fn.mode() == 'V' then
    if srow > erow then
      return vim.api.nvim_buf_get_lines(0, erow - 1, srow, true)
    else
      return vim.api.nvim_buf_get_lines(0, srow - 1, erow, true)
    end
  end

  if vim.fn.mode() == 'v' then
    if srow < erow or (srow == erow and scol <= ecol) then
      return vim.api.nvim_buf_get_text(0, srow - 1, scol - 1, erow - 1, ecol, {})
    else
      return vim.api.nvim_buf_get_text(0, erow - 1, ecol - 1, srow - 1, scol, {})
    end
  end

  if vim.fn.mode() == '\22' then
    local lines = {}
    if srow > erow then
      srow, erow = erow, srow
    end
    if scol > ecol then
      scol, ecol = ecol, scol
    end
    for i = srow, erow do
      table.insert(lines, vim.api.nvim_buf_get_text(0, i - 1, math.min(scol - 1, ecol), i - 1, math.max(scol - 1, ecol), {})[1])
    end
    return lines
  end
end

function M.make_anthropic_spec_curl_args(opts, prompt, system_prompt)
  local url = opts.url
  if not url or url == "" then
    vim.notify("No URL provided for Anthropic API", vim.log.levels.ERROR)
    return nil
  end
  
  local api_key = opts.api_key_name and get_api_key(opts.api_key_name)
  if not api_key then return nil end
  
  local data = {
    system = system_prompt,
    messages = { { role = 'user', content = prompt } },
    model = opts.model,
    stream = true,
    max_tokens = 4096,
  }
  
  local args = { '-N', '-X', 'POST', '-H', 'Content-Type: application/json', '-d', vim.json.encode(data) }
  
  table.insert(args, '-H')
  table.insert(args, 'x-api-key: ' .. api_key)
  table.insert(args, '-H')
  table.insert(args, 'anthropic-version: 2023-06-01')
  table.insert(args, url)
  
  return args
end

function M.make_openai_spec_curl_args(opts, prompt, system_prompt)
  local url = opts.url
  if not url or url == "" then
    vim.notify("No URL provided for OpenAI API", vim.log.levels.ERROR)
    return nil
  end
  
  local api_key = opts.api_key_name and get_api_key(opts.api_key_name)
  if not api_key then return nil end
  
  local data = {
    model = opts.model,
    messages = {
      { role = "system", content = system_prompt },
      { role = "user", content = prompt }
    },
    stream = true,
  }
  
  local args = { '-N', '-X', 'POST', '-H', 'Content-Type: application/json', '-d', vim.json.encode(data) }
  
  table.insert(args, '-H')
  table.insert(args, 'Authorization: Bearer ' .. api_key)
  table.insert(args, url)
  
  return args
end

function M.make_gemini_spec_curl_args(opts, prompt, system_prompt)
  local api_key = opts.api_key_name and get_api_key(opts.api_key_name)
  if not api_key then return nil end
  
  if not opts.model or opts.model == "" then
    vim.notify("No model provided for Gemini API", vim.log.levels.ERROR)
    return nil
  end
  
  local url = "https://generativelanguage.googleapis.com/v1beta/models/" .. opts.model .. ":generateContent?key=" .. api_key
  
  local data = {
    contents = {
      {
        role = "user",
        parts = {
          { text = prompt }
        }
      }
    },
    generationConfig = {
      temperature = 0.7,
      maxOutputTokens = 4096
    },
    systemInstruction = {
      parts = {
        { text = system_prompt }
      }
    }
  }
  
  local args = { '-N', '-X', 'POST', '-H', 'Content-Type: application/json', '-d', vim.json.encode(data) }
  table.insert(args, url)
  
  return args
end

function M.write_string_at_cursor(str)
  vim.schedule(function()
    local current_window = vim.api.nvim_get_current_win()
    local cursor_position = vim.api.nvim_win_get_cursor(current_window)
    local row, col = cursor_position[1], cursor_position[2]

    local lines = vim.split(str, '\n')

    vim.cmd("undojoin")
    vim.api.nvim_put(lines, 'c', true, true)

    local num_lines = #lines
    local last_line_length = #lines[num_lines]
    vim.api.nvim_win_set_cursor(current_window, { row + num_lines - 1, col + last_line_length })
  end)
end

local function get_prompt(opts)
  local replace = opts.replace
  local visual_lines = M.get_visual_selection()
  local prompt = ''

  if visual_lines then
    prompt = table.concat(visual_lines, '\n')
    if replace then
      vim.api.nvim_command 'normal! d'
      vim.api.nvim_command 'normal! k'
    else
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', false, true, true), 'nx', false)
    end
  else
    prompt = M.get_lines_until_cursor()
  end

  return prompt
end

function M.handle_anthropic_spec_data(data_stream, event_state)
  if not data_stream or data_stream == "" then
    return
  end
  
  if data_stream:match("error") then
    vim.schedule(function()
      vim.notify("Anthropic API Error: " .. data_stream, vim.log.levels.ERROR)
    end)
    return
  end

  if event_state == 'content_block_delta' then
    local success, json = pcall(vim.json.decode, data_stream)
    if success and json.delta and json.delta.text then
      M.write_string_at_cursor(json.delta.text)
    elseif not success then
      vim.schedule(function()
        vim.notify("Failed to parse Anthropic JSON: " .. data_stream:sub(1, 100), vim.log.levels.ERROR)
      end)
    end
  end
end

function M.handle_openai_spec_data(data_stream)
  if not data_stream or data_stream == "" then
    return
  end
  
  if data_stream:match("error") then
    vim.schedule(function()
      vim.notify("OpenAI API Error: " .. data_stream, vim.log.levels.ERROR)
    end)
    return
  end

  if data_stream:match '"delta":' then
    local success, json = pcall(vim.json.decode, data_stream)
    if success and json.choices and json.choices[1] and json.choices[1].delta then
      local content = json.choices[1].delta.content
      if content then
        M.write_string_at_cursor(content)
      end
    elseif not success then
      vim.schedule(function()
        vim.notify("Failed to parse OpenAI JSON: " .. data_stream:sub(1, 100), vim.log.levels.ERROR)
      end)
    end
  end
end

function M.handle_gemini_spec_data(data_stream)
  if not data_stream or data_stream == "" then
    return
  end
  
  if data_stream:match("error") then
    vim.schedule(function()
      vim.notify("Gemini API Error: " .. data_stream, vim.log.levels.ERROR)
    end)
    return
  end

  local success, json = pcall(vim.json.decode, data_stream)
  if success and json.candidates and json.candidates[1] and json.candidates[1].content then
    local content = json.candidates[1].content.parts[1].text
    if content then
      M.write_string_at_cursor(content)
    end
  elseif not success then
    vim.schedule(function()
      vim.notify("Failed to parse Gemini JSON: " .. data_stream:sub(1, 100), vim.log.levels.ERROR)
    end)
  end
end

local group = vim.api.nvim_create_augroup('LLM_AutoGroup', { clear = true })
local active_job = nil

function M.invoke_llm_and_stream_into_editor(opts, make_curl_args_fn, handle_data_fn)
  vim.api.nvim_clear_autocmds { group = group }
  local prompt = get_prompt(opts)
  
  if not prompt or prompt == "" then
    vim.notify("Empty prompt. Nothing to send to LLM.", vim.log.levels.WARN)
    return
  end
  
  local system_prompt = opts.system_prompt or 'You are a helpful assistant.'
  local args = make_curl_args_fn(opts, prompt, system_prompt)
  
  if not args then
    vim.notify("Failed to create curl arguments. Please check your configuration.", vim.log.levels.ERROR)
    return
  end
  
  local curr_event_state = nil
  
  -- Create a status notification
  vim.notify("Sending request to " .. (opts.model or "Unknown model"), vim.log.levels.INFO)
  
  local function parse_and_call(line)
    if not line or line == "" then return end
    
    local event = line:match '^event: (.+)$'
    if event then
      curr_event_state = event
      return
    end
    
    local data_match = line:match '^data: (.+)$'
    if data_match then
      if data_match == "[DONE]" then
        vim.schedule(function()
          vim.notify("LLM request completed successfully", vim.log.levels.INFO)
        end)
        return
      end
      handle_data_fn(data_match, curr_event_state)
    else
      -- Handle data that doesn't follow the event format (like Gemini)
      handle_data_fn(line, curr_event_state)
    end
  end

  if active_job then
    active_job:shutdown()
    active_job = nil
  end

  active_job = Job:new {
    command = 'curl',
    args = args,
    on_stdout = function(_, out)
      if out and out ~= "" then
        parse_and_call(out)
      end
    end,
    on_stderr = function(_, err)
      vim.schedule(function()
        if err and err ~= "" then
          vim.notify("LLM Error: " .. err, vim.log.levels.ERROR)
        end
      end)
    end,
    on_exit = function(_, exit_code)
      active_job = nil
      vim.schedule(function()
        vim.api.nvim_del_keymap('n', '<Esc>')
        if exit_code ~= 0 then
          vim.notify("LLM request failed with exit code: " .. tostring(exit_code), vim.log.levels.ERROR)
        end
      end)
    end,
  }

  active_job:start()

  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'LLM_Escape',
    callback = function()
      if active_job then
        active_job:shutdown()
        vim.notify('LLM streaming cancelled', vim.log.levels.INFO)
        active_job = nil
        vim.api.nvim_del_keymap('n', '<Esc>')
      end
    end,
  })

  vim.api.nvim_set_keymap('n', '<Esc>', ':doautocmd User LLM_Escape<CR>', { noremap = true, silent = true })
  return active_job
end

return M
