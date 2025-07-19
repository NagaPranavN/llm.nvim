local M = {}
local Job = require('plenary.job')

local function get_api_key(name)
  local key = os.getenv(name)
  if not key or key == "" then
    vim.notify("API key for " .. name .. " not found in environment variables", vim.log.levels.ERROR)
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
  local _, srow, scol = unpack(vim.fn.getpos('v'))
  local _, erow, ecol = unpack(vim.fn.getpos('.'))

  if vim.fn.mode() == 'V' then
    -- Line-wise visual mode
    if srow > erow then
      return vim.api.nvim_buf_get_lines(0, erow - 1, srow, true)
    else
      return vim.api.nvim_buf_get_lines(0, srow - 1, erow, true)
    end
  end

  if vim.fn.mode() == 'v' then
    -- Character-wise visual mode
    if srow < erow or (srow == erow and scol <= ecol) then
      return vim.api.nvim_buf_get_text(0, srow - 1, scol - 1, erow - 1, ecol, {})
    else
      return vim.api.nvim_buf_get_text(0, erow - 1, ecol - 1, srow - 1, scol, {})
    end
  end

  if vim.fn.mode() == '\22' then
    -- Block-wise visual mode
    local lines = {}
    if srow > erow then
      srow, erow = erow, srow
    end
    if scol > ecol then
      scol, ecol = ecol, scol
    end
    for i = srow, erow do
      table.insert(lines, vim.api.nvim_buf_get_text(0, i - 1, scol - 1, i - 1, ecol, {})[1])
    end
    return lines
  end
  
  return {}
end

-- Enhanced debug logging with structured output
local debug_buffer = nil
local debug_window = nil
local debug_log_queue = {}
local debug_window_visible = false

-- Function to safely create debug window (only called in UI context)
function M.create_debug_window()
  -- Create debug buffer if it doesn't exist
  if not debug_buffer or not vim.api.nvim_buf_is_valid(debug_buffer) then
    debug_buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(debug_buffer, "bufhidden", "hide")
    vim.api.nvim_buf_set_name(debug_buffer, "LLM Debug Log")
  end
  
  -- Create window if it doesn't exist or isn't valid
  if not debug_window or not vim.api.nvim_win_is_valid(debug_window) then
    -- Save current window to return to it later
    local current_win = vim.api.nvim_get_current_win()
    
    -- Create a split window at the bottom
    vim.cmd('botright split')
    debug_window = vim.api.nvim_get_current_win()
    
    -- Set the buffer for this window
    vim.api.nvim_win_set_buf(debug_window, debug_buffer)
    
    -- Set window height
    vim.api.nvim_win_set_height(debug_window, 15)
    
    -- Return to the original window
    vim.api.nvim_set_current_win(current_win)
    
    -- Set window as visible
    debug_window_visible = true
    vim.notify("LLM Debug window opened", vim.log.levels.INFO)
  end
  
  -- Process any queued messages
  if #debug_log_queue > 0 then
    vim.schedule(function()
      if debug_buffer and vim.api.nvim_buf_is_valid(debug_buffer) then
        vim.api.nvim_buf_set_option(debug_buffer, "modifiable", true)
        local line_count = vim.api.nvim_buf_line_count(debug_buffer)
        for _, msg in ipairs(debug_log_queue) do
          local lines = vim.split(msg, "\n")
          vim.api.nvim_buf_set_lines(debug_buffer, line_count, line_count, false, lines)
          line_count = line_count + #lines
        end
        vim.api.nvim_buf_set_option(debug_buffer, "modifiable", false)
        
        -- Auto-scroll to bottom if debug window exists
        if debug_window and vim.api.nvim_win_is_valid(debug_window) then
          vim.api.nvim_win_set_cursor(debug_window, {line_count, 0})
        end
      end
      debug_log_queue = {}
    end)
  end
  
  return debug_buffer
end

-- Close the debug window
function M.close_debug_window()
  if debug_window and vim.api.nvim_win_is_valid(debug_window) then
    vim.api.nvim_win_close(debug_window, true)
    debug_window = nil
    debug_window_visible = false
    vim.notify("LLM Debug window closed", vim.log.levels.INFO)
    return true
  end
  return false
end

-- Structured logging function with different log levels
function M.log_debug(message, level, category)
  level = level or "INFO"
  category = category or "GENERAL"
  local timestamp = os.date("%H:%M:%S")
  local formatted_message = string.format("[%s] [%s] [%s] %s", timestamp, level, category, message)
  
  -- Queue the message
  table.insert(debug_log_queue, formatted_message)
  
  -- Schedule the actual UI update for later
  vim.schedule(function()
    if #debug_log_queue > 0 then
      if not debug_buffer or not vim.api.nvim_buf_is_valid(debug_buffer) then
        M.create_debug_window()
      else
        -- Process the queue directly
        vim.api.nvim_buf_set_option(debug_buffer, "modifiable", true)
        local line_count = vim.api.nvim_buf_line_count(debug_buffer)
        for _, msg in ipairs(debug_log_queue) do
          local lines = vim.split(msg, "\n")
          vim.api.nvim_buf_set_lines(debug_buffer, line_count, line_count, false, lines)
          line_count = line_count + #lines
        end
        vim.api.nvim_buf_set_option(debug_buffer, "modifiable", false)
        
        -- Auto-scroll to bottom if debug window exists
        if debug_window and vim.api.nvim_win_is_valid(debug_window) then
          vim.api.nvim_win_set_cursor(debug_window, {line_count, 0})
        end
        
        debug_log_queue = {}
      end
    end
  end)
end

-- Helper functions for different log levels
function M.log_info(message, category)
  M.log_debug(message, "INFO", category)
end

function M.log_warning(message, category)
  M.log_debug(message, "WARN", category)
end

function M.log_error(message, category)
  M.log_debug(message, "ERROR", category)
end

-- Improved toggle debug window function
function M.toggle_debug_window()
  if debug_window_visible then
    M.close_debug_window()
  else
    M.create_debug_window()
  end
end

-- Get debug window status
function M.get_debug_window_status()
  return debug_window_visible
end

-- Helper function to safely log request data without exposing API keys
local function safe_log_request_data(data, provider)
  local safe_data = vim.deepcopy(data)
  -- Don't log the actual request data as it might contain sensitive info
  M.log_info(string.format("Request prepared for %s with model: %s", provider, safe_data.model or "unknown"), "API")
  M.log_info(string.format("Max tokens: %d", safe_data.max_tokens or 4096), "API")
end

-- OpenAI API integration
function M.make_openai_spec_curl_args(opts, prompt, system_prompt)
  local url = opts.url
  local api_key = opts.api_key_name and get_api_key(opts.api_key_name)
  
  if not api_key then
    M.log_error("Failed to get API key for " .. (opts.api_key_name or "unknown"), "AUTH")
    return nil
  end
  
  local data = {
    model = opts.model,
    messages = {
      { role = "system", content = system_prompt },
      { role = "user", content = prompt }
    },
    stream = true,
    max_tokens = opts.max_tokens or 4096
  }
  
  safe_log_request_data(data, "OpenAI")
  local encoded_data = vim.json.encode(data)
  
  local args = {
    '-N',
    '-X', 'POST',
    '-H', 'Content-Type: application/json',
    '-H', 'Authorization: Bearer ' .. api_key,
    '-d', encoded_data,
    url
  }
  
  M.log_info("OpenAI curl arguments prepared", "API")
  return args
end

-- Anthropic API integration
function M.make_anthropic_spec_curl_args(opts, prompt, system_prompt)
  local url = opts.url
  local api_key = opts.api_key_name and get_api_key(opts.api_key_name)
  
  if not api_key then
    M.log_error("Failed to get API key for " .. (opts.api_key_name or "unknown"), "AUTH")
    return nil
  end
  
  local data = {
    system = system_prompt,
    messages = { { role = 'user', content = prompt } },
    model = opts.model,
    stream = true,
    max_tokens = opts.max_tokens or 4096,
  }
  
  safe_log_request_data(data, "Anthropic")
  local encoded_data = vim.json.encode(data)
  
  local args = {
    '-N',
    '-X', 'POST',
    '-H', 'Content-Type: application/json',
    '-H', 'x-api-key: ' .. api_key,
    '-H', 'anthropic-version: 2023-06-01',
    '-d', encoded_data,
    url
  }
  
  M.log_info("Anthropic curl arguments prepared", "API")
  return args
end

-- Fixed Gemini API integration
function M.make_gemini_spec_curl_args(opts, prompt, system_prompt)
  local api_key = opts.api_key_name and get_api_key(opts.api_key_name)
  
  if not api_key then
    M.log_error("Failed to get API key for " .. (opts.api_key_name or "unknown"), "AUTH")
    return nil
  end
  
  local model = opts.model or "gemini-2.0-flash"
  -- Use the correct streaming endpoint
  local url = "https://generativelanguage.googleapis.com/v1beta/models/" .. model .. ":streamGenerateContent?alt=sse&key=" .. api_key
  
  local data = {
    contents = {
      {
        role = "user",
        parts = {
          { text = prompt }
        }
      }
    },
    systemInstruction = {
      parts = {
        { text = system_prompt }
      }
    },
    generationConfig = {
      maxOutputTokens = opts.max_tokens or 4096
    }
  }
  
  safe_log_request_data(data, "Gemini")
  local encoded_data = vim.json.encode(data)
  
  local args = {
    '-N',
    '-X', 'POST',
    '-H', 'Content-Type: application/json',
    '-H', 'Accept: text/event-stream',
    '-d', encoded_data,
    url
  }
  
  M.log_info("Gemini curl arguments prepared with streaming endpoint", "API")
  return args
end

function M.write_string_at_cursor(str)
  vim.schedule(function()
    local current_window = vim.api.nvim_get_current_win()
    local cursor_position = vim.api.nvim_win_get_cursor(current_window)
    local row, col = cursor_position[1], cursor_position[2]

    local lines = vim.split(str, '\n')

    -- Ensure we're in the same undoable action
    vim.cmd("undojoin")
    vim.api.nvim_put(lines, 'c', true, true)

    -- Update cursor position
    local num_lines = #lines
    local last_line_length = #lines[num_lines]
    vim.api.nvim_win_set_cursor(current_window, { row + num_lines - 1, col + last_line_length })
  end)
end

local function get_prompt(opts)
  local replace = opts.replace
  local visual_lines = M.get_visual_selection()
  local prompt = ''

  if visual_lines and #visual_lines > 0 then
    prompt = table.concat(visual_lines, '\n')
    if replace then
      vim.api.nvim_command('normal! d')
      vim.api.nvim_command('normal! k')
    else
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', false, true, true), 'nx', false)
    end
  else
    prompt = M.get_lines_until_cursor()
  end

  return prompt
end

-- Handle Anthropic API response
function M.handle_anthropic_spec_data(data_stream, event_state)
  M.log_info("Received data, event: " .. (event_state or "none"), "ANTHROPIC")
  
  if event_state == 'content_block_delta' then
    local ok, json = pcall(vim.json.decode, data_stream)
    if ok and json.delta and json.delta.text then
      M.log_info("Writing text: " .. string.sub(json.delta.text, 1, 50) .. "...", "ANTHROPIC")
      M.write_string_at_cursor(json.delta.text)
    elseif not ok then
      M.log_error("Failed to parse JSON: " .. string.sub(data_stream, 1, 100), "ANTHROPIC")
    end
  end
end

-- Handle OpenAI API response
function M.handle_openai_spec_data(data_stream)
  M.log_info("Received data", "OPENAI")
  
  if data_stream:match('"delta":') then
    local ok, json = pcall(vim.json.decode, data_stream)
    if ok and json.choices and json.choices[1] and json.choices[1].delta then
      local content = json.choices[1].delta.content
      if content then
        M.log_info("Writing text: " .. string.sub(content, 1, 50) .. "...", "OPENAI")
        M.write_string_at_cursor(content)
      end
    elseif not ok then
      M.log_error("Failed to parse JSON: " .. string.sub(data_stream, 1, 100), "OPENAI")
    end
  end
end

-- Improved Gemini API response handler
function M.handle_gemini_spec_data(data_stream)
  M.log_info("Received data: " .. string.sub(data_stream, 1, 100), "GEMINI")
  
  -- Skip empty lines and DONE markers
  if data_stream == nil or data_stream == "" or data_stream == "[DONE]" then
    M.log_info("Skipping empty or DONE marker", "GEMINI")
    return
  end
  
  -- Handle SSE format
  if data_stream:match("^data: ") then
    local json_data = data_stream:gsub("^data: ", "")
    if json_data == "" or json_data == "[DONE]" then
      M.log_info("Stream ended", "GEMINI")
      return
    end
    
    local ok, json = pcall(vim.json.decode, json_data)
    if ok and json.candidates and json.candidates[1] then
      local candidate = json.candidates[1]
      if candidate.content and candidate.content.parts and candidate.content.parts[1] then
        local text = candidate.content.parts[1].text
        if text then
          M.log_info("Writing SSE text: " .. string.sub(text, 1, 50) .. "...", "GEMINI")
          M.write_string_at_cursor(text)
          return
        end
      end
    else
      M.log_warning("Could not parse SSE JSON or no content found", "GEMINI")
    end
  end
  
  -- Handle regular JSON format
  local ok, json = pcall(vim.json.decode, data_stream)
  if ok then
    if json.candidates and json.candidates[1] and json.candidates[1].content then
      local parts = json.candidates[1].content.parts
      if parts and parts[1] and parts[1].text then
        local text = parts[1].text
        M.log_info("Writing JSON text: " .. string.sub(text, 1, 50) .. "...", "GEMINI")
        M.write_string_at_cursor(text)
        return
      end
    end
    
    -- Check for error messages
    if json.error then
      M.log_error("API Error: " .. (json.error.message or "Unknown error"), "GEMINI")
      vim.notify("Gemini API Error: " .. (json.error.message or "Unknown error"), vim.log.levels.ERROR)
      return
    end
  end
  
  -- If we get here, we couldn't parse the response
  M.log_warning("Could not extract text from response", "GEMINI")
end

local group = vim.api.nvim_create_augroup('LLM_AutoGroup', { clear = true })
local active_job = nil

function M.invoke_llm_and_stream_into_editor(opts, make_curl_args_fn, handle_data_fn)
  vim.api.nvim_clear_autocmds({ group = group })
  
  -- Ensure debug buffer is created (but only make visible if debug mode is active)
  vim.schedule(function()
    if debug_window_visible then
      M.create_debug_window()
    else
      -- Just ensure the buffer exists without showing it
      if not debug_buffer or not vim.api.nvim_buf_is_valid(debug_buffer) then
        debug_buffer = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_option(debug_buffer, "bufhidden", "hide")
        vim.api.nvim_buf_set_name(debug_buffer, "LLM Debug Log")
      end
    end
  end)
  
  local prompt = get_prompt(opts)
  local system_prompt = opts.system_prompt or 'You are a helpful assistant.'
  
  M.log_info("=== Starting LLM Request ===", "REQUEST")
  M.log_info("Model: " .. (opts.model or "unknown"), "REQUEST")
  M.log_info("URL: " .. (opts.url or "constructed dynamically"), "REQUEST")
  M.log_info("Prompt length: " .. #prompt .. " chars", "REQUEST")
  M.log_info("System prompt length: " .. #system_prompt .. " chars", "REQUEST")
  
  local args = make_curl_args_fn(opts, prompt, system_prompt)
  
  if not args then
    M.log_error("Failed to create curl arguments. Check API key.", "REQUEST")
    return
  end
  
  local curr_event_state = nil
  local stderr_lines = {}
  local buffer = ""  -- Buffer for accumulating partial JSON responses
  local response_count = 0

  local function parse_and_call(line)
    response_count = response_count + 1
    M.log_info("Response #" .. response_count .. ": " .. string.sub(line, 1, 100), "RESPONSE")
    
    -- Check for Anthropic event markers
    local event = line:match('^event: (.+)$')
    if event then
      curr_event_state = event
      M.log_info("Event state changed to: " .. event, "RESPONSE")
      return
    end
    
    -- Check for data lines in SSE format
    local data_match = line:match('^data: (.+)$')
    if data_match then
      handle_data_fn(data_match, curr_event_state)
      return
    end
    
    -- Special handling for Gemini API
    -- Look for complete JSON objects
    buffer = buffer .. line
    
    -- Check if we have a complete JSON object
    if buffer:match("^%s*{") and buffer:match("}%s*$") then
      handle_data_fn(buffer, curr_event_state)
      buffer = ""  -- Reset buffer after handling
    else
      -- For non-JSON lines or incomplete JSON objects
      if not buffer:match("^%s*{") then
        -- If not the start of a JSON object, process directly
        handle_data_fn(line, curr_event_state)
        buffer = ""  -- Reset buffer
      end
      -- Otherwise continue accumulating for an incomplete JSON object
    end
  end

  if active_job then
    active_job:shutdown()
    active_job = nil
  end

  -- Create status message
  local status_msg = vim.api.nvim_echo({ { "LLM is processing...", "WarningMsg" } }, true, {})

  active_job = Job:new({
    command = 'curl',
    args = args,
    on_stdout = function(_, out)
      M.log_info("STDOUT: " .. string.sub(out, 1, 100), "CURL")
      parse_and_call(out)
    end,
    on_stderr = function(_, err)
      if err and err ~= "" then
        -- Only log important stderr messages, not curl progress
        if not err:match("^%s*[%%*]") and not err:match("^%s*{") and not err:match("^%s*<") then
          table.insert(stderr_lines, err)
          M.log_warning("STDERR: " .. err, "CURL")
        end
      end
    end,
    on_exit = function(_, exit_code)
      -- Process any remaining buffer content
      if buffer ~= "" then
        handle_data_fn(buffer, curr_event_state)
      end
      
      M.log_info("=== Request Completed ===", "REQUEST")
      M.log_info("Exit code: " .. exit_code, "REQUEST")
      M.log_info("Total responses: " .. response_count, "REQUEST")
      
      if exit_code ~= 0 then
        vim.schedule(function()
          local err_msg = "LLM request failed with exit code: " .. exit_code
          if #stderr_lines > 0 then
            err_msg = err_msg .. "\nErrors:\n" .. table.concat(stderr_lines, "\n")
          end
          
          vim.notify(err_msg, vim.log.levels.ERROR)
          M.log_error("Request failed: " .. err_msg, "REQUEST")
        end)
      else
        M.log_info("Request completed successfully", "REQUEST")
      end
      
      vim.schedule(function()
        vim.api.nvim_echo({ { "", "" } }, false, {})
        vim.cmd("redraw")
        -- Safely remove the Escape key binding
        pcall(function()
          vim.api.nvim_del_keymap('n', '<Esc>')
        end)
      end)
      
      active_job = nil
    end,
  })

  active_job:start()

  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'LLM_Escape',
    callback = function()
      if active_job then
        active_job:shutdown()
        vim.api.nvim_echo({ { "LLM streaming cancelled", "WarningMsg" } }, false, {})
        M.log_warning("Request cancelled by user", "REQUEST")
        active_job = nil
      end
    end,
  })

  vim.api.nvim_set_keymap('n', '<Esc>', ':doautocmd User LLM_Escape<CR>', { noremap = true, silent = true })
  return active_job
end

-- Register commands for debugging
vim.api.nvim_create_user_command('LLMDebugToggle', function()
  M.toggle_debug_window()
end, { desc = 'Toggle LLM debug window' })

vim.api.nvim_create_user_command('LLMDebugShow', function()
  M.create_debug_window()
end, { desc = 'Show LLM debug window' })

vim.api.nvim_create_user_command('LLMDebugHide', function()
  M.close_debug_window()
end, { desc = 'Hide LLM debug window' })

vim.api.nvim_create_user_command('LLMDebugClear', function()
  if debug_buffer and vim.api.nvim_buf_is_valid(debug_buffer) then
    vim.api.nvim_buf_set_option(debug_buffer, "modifiable", true)
    vim.api.nvim_buf_set_lines(debug_buffer, 0, -1, false, {})
    vim.api.nvim_buf_set_option(debug_buffer, "modifiable", false)
    M.log_info("Debug log cleared", "SYSTEM")
  end
end, { desc = 'Clear LLM debug log' })

return M
