-- This is a wrapper module that ensures proper loading of the llm functions
local M = {}

-- Import the actual implementation
local llm_impl = require("llm")

-- Copy all functions from the implementation
for k, v in pairs(llm_impl) do
  M[k] = v
end

-- Function to get API key with error handling
local function get_api_key(name)
  local key = os.getenv(name)
  if not key or key == "" then
    vim.notify("API key not found: " .. name, vim.log.levels.ERROR)
    return nil
  end
  return key
end

-- Ensure the curl argument functions are available
M.make_anthropic_spec_curl_args = function(opts, prompt, system_prompt)
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

M.make_openai_spec_curl_args = function(opts, prompt, system_prompt)
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

M.make_gemini_spec_curl_args = function(opts, prompt, system_prompt)
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

M.handle_anthropic_spec_data = function(data_stream, event_state)
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

M.handle_openai_spec_data = function(data_stream)
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

M.handle_gemini_spec_data = function(data_stream)
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

return M
