# frozen_string_literal: true

require "test_helper"

class CurationMCPClientTest < ActiveSupport::TestCase
  setup do
    @test_content = "What vulnerabilities are associated with CVE-2023-1234?"
    @client = CurationMCP::Client.new(@test_content)
  end

  test "initializes with correct system and user messages" do
    client = CurationMCP::Client.new("Test content")

    assert_equal 2, client.messages.length

    system_message = client.messages[0]
    assert_equal "system", system_message[:role]
    assert_equal CurationMCP::Client::SYSTEM_PROMPT, system_message[:content]

    user_message = client.messages[1]
    assert_equal "user", user_message[:role]
    assert_equal "Test content", user_message[:content]
  end

  test "initializes with empty content" do
    client = CurationMCP::Client.new("")

    user_message = client.messages[1]
    assert_equal "", user_message[:content]
  end

  test "initializes with nil content" do
    client = CurationMCP::Client.new(nil)

    user_message = client.messages[1]
    assert_nil user_message[:content]
  end

  test "final_response returns content when no tool calls" do
    mock_response = mock("response")
    mock_body = {
      "choices" => [
        {
          "message" => {
            "tool_calls" => nil,
            "content" => "Direct response without tools",
          },
        },
      ],
    }
    mock_response.stubs(:body).returns(mock_body)

    # Mock the MCP client to avoid network calls
    mock_mcp_client = mock("mcp_client")
    mock_mcp_client.stubs(:to_openai_tools).returns([])
    @client.stubs(:mcp_client).returns(mock_mcp_client)

    CopilotAPI::Client.expects(:get_response).with(
      tools: [],
      model: CurationMCP::Client::COPILOT_MODEL,
      messages: @client.messages,
    ).returns(mock_response)

    response = @client.final_response

    assert_equal "Direct response without tools", response
  end

  test "final_response returns content when tool calls are blank array" do
    mock_response = mock("response")
    mock_body = {
      "choices" => [
        {
          "message" => {
            "tool_calls" => [],
            "content" => "Response with empty tool calls",
          },
        },
      ],
    }
    mock_response.stubs(:body).returns(mock_body)

    # Mock the MCP client to avoid network calls
    mock_mcp_client = mock("mcp_client")
    mock_mcp_client.stubs(:to_openai_tools).returns([])
    @client.stubs(:mcp_client).returns(mock_mcp_client)

    CopilotAPI::Client.expects(:get_response).returns(mock_response)

    response = @client.final_response

    assert_equal "Response with empty tool calls", response
  end

  test "final_response processes tool calls and makes second API call" do
    # Mock first response with tool calls
    first_response = mock("first_response")
    first_body = {
      "choices" => [
        {
          "message" => {
            "tool_calls" => [
              {
                "id" => "call_123",
                "function" => {
                  "name" => "search_vulnerability",
                  "arguments" => '{"cve_id": "CVE-2023-1234"}',
                },
              },
            ],
            "content" => nil,
          },
        },
      ],
    }
    first_response.stubs(:body).returns(first_body)

    # Mock second response after tool execution
    second_response = mock("second_response")
    second_body = {
      "choices" => [
        {
          "message" => {
            "tool_calls" => nil,
            "content" => "Found vulnerability information for CVE-2023-1234",
          },
        },
      ],
    }
    second_response.stubs(:body).returns(second_body)

    # Mock MCP client and tool execution
    mock_mcp_client = mock("mcp_client")
    mock_tool_result = { "vulnerability_data" => "some data" }
    mock_mcp_client.stubs(:to_openai_tools).returns([{ "type" => "function", "function" => { "name" => "search_vulnerability" } }])
    mock_mcp_client.expects(:call_tool).with("search_vulnerability", { "cve_id" => "CVE-2023-1234" }).returns(mock_tool_result)
    @client.stubs(:mcp_client).returns(mock_mcp_client)

    # Expect two API calls
    CopilotAPI::Client.expects(:get_response).twice.returns(first_response, second_response)

    response = @client.final_response

    assert_equal "Found vulnerability information for CVE-2023-1234", response

    # Verify messages were updated correctly
    assert_equal 4, @client.messages.length
    assert_equal "assistant", @client.messages[2][:role]
    assert_equal "tool", @client.messages[3][:role]
    assert_equal "call_123", @client.messages[3][:tool_call_id]
    assert_equal "search_vulnerability", @client.messages[3][:name]
    assert_equal mock_tool_result.to_json, @client.messages[3][:content]
  end

  test "final_response handles multiple tool calls" do
    # Mock response with multiple tool calls
    first_response = mock("first_response")
    first_body = {
      "choices" => [
        {
          "message" => {
            "tool_calls" => [
              {
                "id" => "call_1",
                "function" => {
                  "name" => "tool_1",
                  "arguments" => '{"param": "value1"}',
                },
              },
              {
                "id" => "call_2",
                "function" => {
                  "name" => "tool_2",
                  "arguments" => '{"param": "value2"}',
                },
              },
            ],
            "content" => nil,
          },
        },
      ],
    }
    first_response.stubs(:body).returns(first_body)

    second_response = mock("second_response")
    second_body = {
      "choices" => [
        {
          "message" => {
            "tool_calls" => nil,
            "content" => "Multiple tools executed successfully",
          },
        },
      ],
    }
    second_response.stubs(:body).returns(second_body)

    # Mock MCP client
    mock_mcp_client = mock("mcp_client")
    mock_mcp_client.stubs(:to_openai_tools).returns([
      { "type" => "function", "function" => { "name" => "tool_1" } },
      { "type" => "function", "function" => { "name" => "tool_2" } },
    ])
    mock_mcp_client.expects(:call_tool).with("tool_1", { "param" => "value1" }).returns({ "result" => "1" })
    mock_mcp_client.expects(:call_tool).with("tool_2", { "param" => "value2" }).returns({ "result" => "2" })
    @client.stubs(:mcp_client).returns(mock_mcp_client)

    CopilotAPI::Client.expects(:get_response).twice.returns(first_response, second_response)

    response = @client.final_response

    assert_equal "Multiple tools executed successfully", response
    assert_equal 5, @client.messages.length # original 2 + assistant + 2 tool responses
  end

  test "final_response handles JSON parsing errors in tool arguments" do
    first_response = mock("first_response")
    first_body = {
      "choices" => [
        {
          "message" => {
            "tool_calls" => [
              {
                "id" => "call_123",
                "function" => {
                  "name" => "test_tool",
                  "arguments" => "invalid json",
                },
              },
            ],
            "content" => nil,
          },
        },
      ],
    }
    first_response.stubs(:body).returns(first_body)

    # Mock MCP client
    mock_mcp_client = mock("mcp_client")
    mock_mcp_client.stubs(:to_openai_tools).returns([{ "type" => "function", "function" => { "name" => "test_tool" } }])
    @client.stubs(:mcp_client).returns(mock_mcp_client)

    CopilotAPI::Client.expects(:get_response).returns(first_response)
    GitHub::Telemetry::Logs.logger.expects(:error).with(regexp_matches(/Error calling Curation MCP tool:/))

    error = assert_raises(RuntimeError) do
      @client.final_response
    end

    assert_equal CurationMCP::Client::USER_FRIENDLY_ERROR, error.message
  end

  test "final_response handles MCP client errors" do
    first_response = mock("first_response")
    first_body = {
      "choices" => [
        {
          "message" => {
            "tool_calls" => [
              {
                "id" => "call_123",
                "function" => {
                  "name" => "test_tool",
                  "arguments" => '{"param": "value"}',
                },
              },
            ],
            "content" => nil,
          },
        },
      ],
    }
    first_response.stubs(:body).returns(first_body)

    mock_mcp_client = mock("mcp_client")
    mock_mcp_client.stubs(:to_openai_tools).returns([{ "type" => "function", "function" => { "name" => "test_tool" } }])
    mock_mcp_client.expects(:call_tool).raises(StandardError.new("MCP connection failed"))
    @client.stubs(:mcp_client).returns(mock_mcp_client)

    CopilotAPI::Client.expects(:get_response).returns(first_response)
    GitHub::Telemetry::Logs.logger.expects(:error).with("Error calling Curation MCP tool: MCP connection failed")

    error = assert_raises(RuntimeError) do
      @client.final_response
    end

    assert_equal CurationMCP::Client::USER_FRIENDLY_ERROR, error.message
  end

  test "final_response handles CopilotAPI errors" do
    # Mock the MCP client to avoid network calls
    mock_mcp_client = mock("mcp_client")
    mock_mcp_client.stubs(:to_openai_tools).returns([])
    @client.stubs(:mcp_client).returns(mock_mcp_client)

    CopilotAPI::Client.expects(:get_response).raises(StandardError.new("API connection failed"))
    GitHub::Telemetry::Logs.logger.expects(:error).with("Error calling Curation MCP tool: API connection failed")

    error = assert_raises(RuntimeError) do
      @client.final_response
    end

    assert_equal CurationMCP::Client::USER_FRIENDLY_ERROR, error.message
  end
end
