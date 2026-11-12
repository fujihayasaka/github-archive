# frozen_string_literal: true

require "test_helper"

class CopilotChatControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user)
    @valid_message = "Help me understand this CVE vulnerability"
    AdvisoryDB::Config::CurationMCP.stubs(:chat_disabled?).returns(false)
  end

  test "chat returns success with valid message" do
    mock_response = "Here's information about the CVE vulnerability..."

    CurationMCP::Client.any_instance.expects(:final_response).returns(mock_response)

    post "/chat",
      headers: { "X-Okta-Username" => @user.email },
      params: { message: @valid_message },
      xhr: true

    assert_response :ok

    response_json = response.parsed_body
    assert response_json["message"].present?
    assert_includes response_json["message"], "Here's information about the CVE vulnerability"
  end

  test "chat rejects blank message" do
    post "/chat",
      headers: { "X-Okta-Username" => @user.email },
      params: { message: "" },
      xhr: true

    assert_response :unprocessable_content

    response_json = response.parsed_body
    assert_equal "Message can't be blank", response_json["error"]
  end

  test "chat rejects nil message" do
    post "/chat",
      headers: { "X-Okta-Username" => @user.email },
      params: { message: nil },
      xhr: true

    assert_response :unprocessable_content

    response_json = response.parsed_body
    assert_equal "Message can't be blank", response_json["error"]
  end

  test "chat rejects whitespace-only message" do
    post "/chat",
      headers: { "X-Okta-Username" => @user.email },
      params: { message: "   \n\t   " },
      xhr: true

    assert_response :unprocessable_content

    response_json = response.parsed_body
    assert_equal "Message can't be blank", response_json["error"]
  end

  test "chat processes markdown in response" do
    markdown_response = "## CVE Analysis\n\nThis is **important** information."

    CurationMCP::Client.any_instance.expects(:final_response).returns(markdown_response)

    post "/chat",
      headers: { "X-Okta-Username" => @user.email },
      params: { message: @valid_message },
      xhr: true

    assert_response :ok

    response_json = response.parsed_body
    # Should contain HTML tags from markdown processing
    assert_includes response_json["message"], "<h2>"
    assert_includes response_json["message"], "<strong>"
  end

  test "chat handles CurationMCP::Client errors gracefully" do
    CurationMCP::Client.any_instance.expects(:final_response).raises(StandardError.new("MCP service unavailable"))

    post "/chat",
      headers: { "X-Okta-Username" => @user.email },
      params: { message: @valid_message },
      xhr: true

    assert_response :unprocessable_content

    response_json = response.parsed_body
    assert_equal "MCP service unavailable", response_json["error"]
  end

  test "chat requires authentication" do
    post "/chat",
      params: { message: @valid_message },
      xhr: true

    assert_response :forbidden
  end

  test "chat returns JSON content type" do
    CurationMCP::Client.any_instance.expects(:final_response).returns("Test response")

    post "/chat",
      headers: { "X-Okta-Username" => @user.email },
      params: { message: @valid_message },
      xhr: true

    assert_response :ok
    assert_equal "application/json; charset=utf-8", response.content_type
  end

  test "chat handles long messages" do
    long_message = "What can you tell me about this vulnerability? " * 50
    mock_response = "Analysis of the vulnerability..."

    CurationMCP::Client.any_instance.expects(:final_response).returns(mock_response)

    post "/chat",
      headers: { "X-Okta-Username" => @user.email },
      params: { message: long_message },
      xhr: true

    assert_response :ok

    response_json = response.parsed_body
    assert response_json["message"].present?
  end

  test "chat handles special characters safely" do
    special_message = "What about <script>alert('xss')</script> and SQL injection?"
    mock_response = "Security analysis response"

    CurationMCP::Client.any_instance.expects(:final_response).returns(mock_response)

    post "/chat",
      headers: { "X-Okta-Username" => @user.email },
      params: { message: special_message },
      xhr: true

    assert_response :ok

    response_json = response.parsed_body
    assert response_json["message"].present?
  end

  test "chat returns error when chat is disabled" do
    AdvisoryDB::Config::CurationMCP.stubs(:chat_disabled?).returns(true)

    post "/chat",
      headers: { "X-Okta-Username" => @user.email },
      params: { message: @valid_message },
      xhr: true

    assert_response :unprocessable_content

    response_json = response.parsed_body
    assert_equal "Chat is disabled", response_json["error"]
  end
end
