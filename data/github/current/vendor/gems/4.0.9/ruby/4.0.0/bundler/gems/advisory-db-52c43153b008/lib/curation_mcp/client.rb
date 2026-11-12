# frozen_string_literal: true

require "mcp_client"

module CurationMCP
  class Client
    SYSTEM_PROMPT = "You are a security analyst that specializes in security advisories."
    COPILOT_MODEL = "gpt-4o"
    USER_FRIENDLY_ERROR = "Failed to get a valid response from Copilot and the MCP tools. Please try again later."

    attr_reader :messages

    def initialize(content)
      @messages = build_initial_messages(content)
    end

    def final_response
      tool_calls, content_response = copilot_response

      return content_response if no_tools_requested?(tool_calls)

      process_tool_calls(tool_calls)
      final_copilot_response
    rescue StandardError => error
      log_error(error)
      raise USER_FRIENDLY_ERROR
    end

    private

    def build_initial_messages(content)
      [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: content },
      ]
    end

    def copilot_response(tools: mcp_tools)
      response = CopilotAPI::Client.get_response(
        tools: tools,
        model: COPILOT_MODEL,
        messages: messages,
      )

      message = extract_message_from_response(response)
      [message&.dig("tool_calls"), message&.dig("content")]
    end

    def extract_message_from_response(response)
      response.body&.dig("choices", 0, "message")
    end

    def no_tools_requested?(tool_calls)
      tool_calls.blank?
    end

    def process_tool_calls(tool_calls)
      add_assistant_message(tool_calls)
      execute_tools(tool_calls)
    end

    def add_assistant_message(tool_calls)
      @messages << { role: "assistant", tool_calls: tool_calls }
    end

    def execute_tools(tool_calls)
      tool_calls.each do |tool|
        result = execute_single_tool(tool)
        add_tool_result_message(tool, result)
      end
    end

    def execute_single_tool(tool)
      function_call = tool["function"]
      name = function_call["name"]
      args = parse_tool_arguments(function_call["arguments"])

      mcp_client.call_tool(name, args)
    end

    def parse_tool_arguments(arguments_json)
      JSON.parse(arguments_json)
    end

    def add_tool_result_message(tool, result)
      @messages << {
        role: "tool",
        tool_call_id: tool["id"],
        name: tool["function"]["name"],
        content: result.to_json,
      }
    end

    def final_copilot_response
      _, content_response = copilot_response(tools: [])
      content_response
    end

    def log_error(error)
      GitHub::Telemetry::Logs.logger.error("Error calling Curation MCP tool: #{error.message}")
    end

    def mcp_tools
      @mcp_tools ||= mcp_client.to_openai_tools
    end

    def mcp_client
      @mcp_client ||= create_mcp_client
    end

    def create_mcp_client
      MCPClient.create_client(
        mcp_server_configs: [
          MCPClient.streamable_http_config(
            base_url: AdvisoryDB::Config::CurationMCP.server_base_url,
            endpoint: "/mcp/",
          ),
        ],
      )
    end
  end
end
