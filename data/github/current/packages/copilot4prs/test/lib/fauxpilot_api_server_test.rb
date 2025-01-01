# typed: true
# frozen_string_literal: true

require "test_helper"

class FauxpilotApiServerTest < GitHub::TestCase
  include Rack::Test::Methods

  def app
    @app ||= FauxpilotApiServer
  end

  def assert_json_response
    content_type = last_response.headers["Content-Type"]
    refute_nil content_type
    assert_includes content_type, "application/json"
  end

  def assert_cors_header
    access_control_allow_origin = last_response.headers["Access-Control-Allow-Origin"]
    assert_equal "*", access_control_allow_origin
  end

  context "GET /github/chat/threads" do
    test "succeeds" do
      get "/github/chat/threads"

      assert_predicate last_response, :ok?
      assert_json_response
      last_payload = JSON.parse(last_response.body)
      assert_instance_of Array, last_payload["threads"]
    end
  end

  context "POST /github/chat/threads" do
    test "succeeds" do
      data = { "some" => "value" }

      post "/github/chat/threads", data.to_json

      assert_predicate last_response, :created?
      assert_json_response
      assert_cors_header
      last_payload = JSON.parse(last_response.body)
      assert_instance_of String, last_payload["thread_id"]
      assert_instance_of Hash, last_payload["thread"]
    end
  end

  context "GET /github/chat/threads/:thread_id/messages" do
    test "succeeds" do
      thread_id = "123abc"

      get "/github/chat/threads/#{thread_id}/messages"

      assert_predicate last_response, :ok?
      assert_json_response
      assert_cors_header
      last_payload = JSON.parse(last_response.body)
      assert_instance_of Hash, last_payload["thread"]
      assert_equal thread_id, last_payload["thread"]["id"]
    end
  end

  context "POST /github/chat/threads/:thread_id/messages" do
    test "succeeds when not streaming" do
      thread_id = "123abc"
      data = { "some" => "value" }

      post "/github/chat/threads/#{thread_id}/messages", data.to_json

      assert_predicate last_response, :ok?
      assert_json_response
      assert_cors_header
      last_payload = JSON.parse(last_response.body)
      assert_instance_of Hash, last_payload["message"]
      assert_equal thread_id, last_payload["message"]["threadID"]
    end

    test "succeeds when streaming" do
      thread_id = "123abc"
      data = { "some" => "value", "streaming" => true }

      post "/github/chat/threads/#{thread_id}/messages", data.to_json

      assert_predicate last_response, :ok?
      assert_cors_header
      resp_body = last_response.body
      assert_predicate resp_body, :present?
      assert_includes resp_body, 'data: {"type":"content","body":"'
      assert_includes resp_body, 'data: {"type":"complete",'
      content_type = last_response.headers["Content-Type"]
      refute_nil content_type
      assert_includes content_type, "text/event-stream"
    end
  end

  context "PATCH /github/chat/threads/:thread_id/name" do
    test "succeeds when providing a name" do
      patch "/github/chat/threads/123abc/name", { "generate" => false, "name" => "new name" }.to_json

      assert_predicate last_response, :ok?
      assert_cors_header
      assert_json_response
      last_payload = JSON.parse(last_response.body)
      assert_equal "new name", last_payload["name"]
    end

    test "succeeds when generating a name" do
      patch "/github/chat/threads/123abc/name", { "generate" => true, "name" => "" }.to_json

      assert_predicate last_response, :ok?
      assert_cors_header
      assert_json_response
      last_payload = JSON.parse(last_response.body)
      assert_instance_of String, last_payload["name"]
      assert_predicate last_payload["name"], :present?
    end
  end

  context "POST /github/chat/threads/:thread_id/messages/:message_id/feedback" do
    test "succeeds" do
      data = { "some" => "value" }

      post "/github/chat/threads/123abc/messages/8675309/feedback", data.to_json

      assert_predicate last_response, :created?
      assert_json_response
      assert_cors_header
    end
  end

  context "POST /agents/github-summary" do
    test "succeeds" do
      data = { "some" => "value" }

      post "/agents/github-summary", data.to_json

      assert_predicate last_response, :ok?
      assert_cors_header
      resp_body = last_response.body
      assert_predicate resp_body, :present?
      assert_includes resp_body, 'data: {"choices":'
      content_type = last_response.headers["Content-Type"]
      refute_nil content_type
      assert_includes content_type, "text/event-stream"
    end
  end
end
