
  {
    'NagaPranavN/pyrepl.nvim',
    dependencies = { 'nvim-lua/plenary.nvim' },
    config = function()
      require("pyrepl").setup({
        url = "http://localhost:5000/execute",
        show_result = true,
        timeout = 10000
      })
    end,
    keys = {
      { "<leader>p", function() require('pyrepl').run_selected_lines() end, mode = "v", desc = "Run selected lines" }
    }
  },

  {
    'NagaPranavN/llm.nvim',
    dependencies = { 'nvim-lua/plenary.nvim' },
    config = function()
      local system_prompt =
        'You should replace the code that you are sent, only following the comments. Do not talk at all. Only output valid code. Do not provide any backticks that surround the code. Never ever output backticks like this ```. Any comment that is asking you for something should be removed after you satisfy them. Other comments should left alone. Do not output backticks'
      local helpful_prompt = 'You are a helpful assistant. What I have sent are my notes so far. You are very curt, yet helpful.'
      local llm = require('llm')

      -- Groq functions
      local function groq_replace()
        llm.invoke_llm_and_stream_into_editor({
          url = 'https://api.groq.com/openai/v1/chat/completions',
          model = 'llama3-70b-8192',
          api_key_name = 'GROQ_API_KEY',
          system_prompt = system_prompt,
          replace = true,
          max_tokens = 4096
        }, llm.make_openai_spec_curl_args, llm.handle_openai_spec_data)
      end

      local function groq_help()
        llm.invoke_llm_and_stream_into_editor({
          url = 'https://api.groq.com/openai/v1/chat/completions',
          model = 'llama3-70b-8192',
          api_key_name = 'GROQ_API_KEY',
          system_prompt = helpful_prompt,
          replace = false,
          max_tokens = 4096
        }, llm.make_openai_spec_curl_args, llm.handle_openai_spec_data)
      end

      -- OpenAI functions
      local function openai_replace()
        llm.invoke_llm_and_stream_into_editor({
          url = 'https://api.openai.com/v1/chat/completions',
          model = 'gpt-4o',
          api_key_name = 'OPENAI_API_KEY',
          system_prompt = system_prompt,
          replace = true,
          max_tokens = 4096
        }, llm.make_openai_spec_curl_args, llm.handle_openai_spec_data)
      end

      local function openai_help()
        llm.invoke_llm_and_stream_into_editor({
          url = 'https://api.openai.com/v1/chat/completions',
          model = 'gpt-4o',
          api_key_name = 'OPENAI_API_KEY',
          system_prompt = helpful_prompt,
          replace = false,
          max_tokens = 4096
        }, llm.make_openai_spec_curl_args, llm.handle_openai_spec_data)
      end

      -- Anthropic functions
      local function anthropic_help()
        llm.invoke_llm_and_stream_into_editor({
          url = 'https://api.anthropic.com/v1/messages',
          model = 'claude-3-5-sonnet-20240620',
          api_key_name = 'ANTHROPIC_API_KEY',
          system_prompt = helpful_prompt,
          replace = false,
          max_tokens = 4096
        }, llm.make_anthropic_spec_curl_args, llm.handle_anthropic_spec_data)
      end

      local function anthropic_replace()
        llm.invoke_llm_and_stream_into_editor({
          url = 'https://api.anthropic.com/v1/messages',
          model = 'claude-3-5-sonnet-20240620',
          api_key_name = 'ANTHROPIC_API_KEY',
          system_prompt = system_prompt,
          replace = true,
          max_tokens = 4096
        }, llm.make_anthropic_spec_curl_args, llm.handle_anthropic_spec_data)
      end

      -- Gemini functions
      local function gemini_help()
        llm.invoke_llm_and_stream_into_editor({
          model = 'gemini-2.0-flash',
          api_key_name = 'GEMINI_API_KEY',
          system_prompt = helpful_prompt,
          replace = false,
          max_tokens = 4096
        }, llm.make_gemini_spec_curl_args, llm.handle_gemini_spec_data)
      end

      local function gemini_replace()
        llm.invoke_llm_and_stream_into_editor({
          model = 'gemini-2.0-flash',
          api_key_name = 'GEMINI_API_KEY',
          system_prompt = system_prompt,
          replace = true,
          max_tokens = 4096
        }, llm.make_gemini_spec_curl_args, llm.handle_gemini_spec_data)
      end

      -- Register keymaps
      vim.keymap.set({ 'n', 'v' }, '<leader>k', groq_replace, { desc = 'LLM: Groq replace' })
      vim.keymap.set({ 'n', 'v' }, '<leader>K', groq_help, { desc = 'LLM: Groq help' })
      vim.keymap.set({ 'n', 'v' }, '<leader>l', openai_replace, { desc = 'LLM: OpenAI replace' })
      vim.keymap.set({ 'n', 'v' }, '<leader>L', openai_help, { desc = 'LLM: OpenAI help' })
      vim.keymap.set({ 'n', 'v' }, '<leader>i', anthropic_replace, { desc = 'LLM: Anthropic replace' })
      vim.keymap.set({ 'n', 'v' }, '<leader>I', anthropic_help, { desc = 'LLM: Anthropic help' })
      vim.keymap.set({ 'n', 'v' }, '<leader>g', gemini_replace, { desc = 'LLM: Gemini replace' })
      vim.keymap.set({ 'n', 'v' }, '<leader>G', gemini_help, { desc = 'LLM: Gemini help' })
      
      -- Add a "cancel LLM" command
      vim.api.nvim_create_user_command('LLMCancel', function()
        vim.cmd('doautocmd User LLM_Escape')
      end, { desc = 'Cancel ongoing LLM request' })
    end,
  }
