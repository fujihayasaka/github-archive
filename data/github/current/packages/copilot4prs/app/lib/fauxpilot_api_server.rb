# typed: true
# frozen_string_literal: true

require "sinatra/base"
unless defined? GitHub::Application
  require_relative "../../../../config/environment"
end
require "faker"

# Public: This is a small web server for use with testing Copilot in local development. It responds to endpoints that
# get exercised when using the Copilot chat interface on the web. You can use this server alongside `script/server`
# so you don't need to clone the github/copilot-api repository into your Codespace.
#
# Run via `bin/fauxpilot-api-server`, or `bin/fauxpilot-api-server PORT_NUMBER_HERE`.
class FauxpilotApiServer < Sinatra::Base
  before do
    content_type :json
    headers "Access-Control-Allow-Origin" => request.env["HTTP_ORIGIN"] || "*"
  end

  THREAD_ID = "b52621db-752c-42b6-a241-75ec13d69b0d"

  # https://github.com/github/copilot-api/blob/6d24b09712e95c0bb3b4e1913b8b32b9ce27f0a2/pkg/rest/chat.go#L100
  get "/github/chat/threads" do
    recent_time = 5.minutes.ago
    name_filter = params[:name]
    fake_thread = {
      "id" => THREAD_ID,
      "name" => name_filter.presence || "",
      "repoID" => 0,
      "repoOwnerID" => 0,
      "createdAt" => recent_time,
      "updatedAt" => recent_time + 1.minute,
      "associatedRepoIDs" => [],
    }
    threads = if name_filter.present?
      # Filtering by name, so randomly return either a matching thread or no matching threads
      if [true, false].sample
        [fake_thread]
      else
        []
      end
    else
      # Not filtering by name, so simulate finding at least one thread
      [fake_thread]
    end
    [200, {}, { "threads" => threads }.to_json]
  end

  # https://github.com/github/copilot-api/blob/6d24b09712e95c0bb3b4e1913b8b32b9ce27f0a2/pkg/rest/chat.go#L98
  post "/github/chat/threads" do
    body_params = body_json_from(request)
    now = Time.current
    [201, {}, {
      "thread_id" => THREAD_ID,
      "thread" => {
        "id" => THREAD_ID,
        "name" => "",
        "repoID" => body_params["repo_id"] || 0,
        "repoOwnerID" => body_params["repo_owner_id"] || 0,
        "createdAt" => now,
        "updatedAt" => now,
        "associatedRepoIDs" => [],
      },
    }.to_json]
  end

  # https://github.com/github/copilot-api/blob/6d24b09712e95c0bb3b4e1913b8b32b9ce27f0a2/pkg/rest/chat.go#L103
  get "/github/chat/threads/:thread_id/messages" do
    thread_id = params["thread_id"]
    recent_time = 5.minutes.ago
    [200, {}, {
      "thread" => {
        "id" => thread_id,
        "name" => "",
        "repoID" => 0,
        "repoOwnerID" => 0,
        "createdAt" => recent_time,
        "updatedAt" => recent_time + 1.minute,
        "currentReferences" => [fake_reference],
        "associatedRepoIDs" => []
      },
      "messages" => [
        {
          "id" => "de581ff8-68d7-4324-a253-f56ab40a69a8",
          "threadID" => thread_id,
          "turnID" => "123d4346-0675-4adf-b7a9-f259e98958c9",
          "role" => "user",
          "content" => "Review",
          "createdAt" => 1.minute.ago,
          "intent" => "review-pull-request",
          "references" => [fake_reference],
          "copilotAnnotations" => nil,
        },
        {
          "id" => "80ddb396-87b9-444c-8173-a89990d1b54a",
          "threadID" => thread_id,
          "turnID" => "123d4346-0675-4adf-b7a9-f259e98958c9",
          "role" => "assistant",
          "content" => fake_copilot_message,
          "createdAt" => 2.minutes.ago,
          "intent" => "review-pull-request",
          "references" => [],
          "copilotAnnotations" => {}
        },
      ],
    }.to_json]
  end

  # https://github.com/github/copilot-api/blob/6d24b09712e95c0bb3b4e1913b8b32b9ce27f0a2/pkg/rest/chat.go#L106
  post "/github/chat/threads/:thread_id/messages" do
    body_params = body_json_from(request)
    if body_params["streaming"]
      content_type "text/event-stream"
      total_messages = rand(5) + 1
      stream do |out|
        total_messages.times do
          data = { "type" => "content", "body" => fake_copilot_message }
          out << "data: #{data.to_json}\n\n"
          sleep 0.3
        end
        data = {
          "type" => "complete",
          "id" => "63d75419-5276-431f-9a9d-68faaa68298b",
          "turnId" => "334a003f-eb6c-4bca-959b-81640360e92f",
          "createdAt"  => Time.current,
          "references" => [],
          "role" => "assistant",
          "intent" => "conversation",
          "copilotAnnotations" => {},
        }
        out << "data: #{data.to_json}\n\n"
      end
    else
      thread_id = params["thread_id"]
      [200, {}, {
        "message" => {
          "id" => "80ddb396-87b9-444c-8173-a89990d1b54a",
          "threadID" => thread_id,
          "turnID" => "123d4346-0675-4adf-b7a9-f259e98958c9",
          "role" => "assistant",
          "content" => fake_copilot_message,
          "createdAt" => Time.current,
          "intent" => body_params["intent"],
          "references" => body_params["references"],
          "copilotAnnotations" => {},
        }
      }.to_json]
    end
  end

  # https://github.com/github/copilot-api/blob/6d24b09712e95c0bb3b4e1913b8b32b9ce27f0a2/pkg/rest/chat.go#L99
  post "/github/chat/threads/:thread_id/messages/:message_id/feedback" do
    [201, {}, {}]
  end

  # https://github.com/github/copilot-api/blob/6d24b09712e95c0bb3b4e1913b8b32b9ce27f0a2/pkg/rest/chat.go#L102
  patch "/github/chat/threads/:thread_id/name" do
    body_params = body_json_from(request)
    name = body_params["generate"] ? Faker::Lorem.sentence : body_params["name"]
    [200, {}, { "name" => name }.to_json]
  end

  options "*" do
    [200, {
      "Access-Control-Allow-Headers" => "*",
      "Access-Control-Allow-Methods" => %w(GET POST PATCH PUT DELETE OPTIONS),
      "Access-Control-Max-Age" => "600",
    }, {}]
  end

  post "/agents/github-summary" do
    data = {
      "choices": [
        {
          "content_filter_results": {
            "error": {
              "code": "",
              "message": ""
            },
            "hate": {
              "filtered": false,
              "severity": "safe"
            },
            "self_harm": {
              "filtered": false,
              "severity": "safe"
            },
            "sexual": {
              "filtered": false,
              "severity": "safe"
            },
            "violence": {
              "filtered": false,
              "severity": "safe"
            }
          },
          "finish_reason": "stop",
          "index": 0,
          "message": {
            "content": fake_copilot_message,
            "padding": "",
            "role": "assistant"
          }
        }
      ],
      "created": 1721662438,
      "id": "chatcmpl-9npKwgG5hdNFsmRCQGeX6JsSCMXox",
      "prompt_filter_results": [
        {
          "content_filter_results": {
            "error": {
              "code": "",
              "message": ""
            },
            "hate": {
              "filtered": false,
              "severity": "safe"
            },
            "self_harm": {
              "filtered": false,
              "severity": "safe"
            },
            "sexual": {
              "filtered": false,
              "severity": "safe"
            },
            "violence": {
              "filtered": false,
              "severity": "safe"
            }
          },
          "prompt_index": 0
        }
      ],
      "usage": {
        "completion_tokens": 52,
        "prompt_tokens": 527,
        "total_tokens": 579
      }
    }

    [200, { "Content-Type" => "text/event-stream" }, "data: #{data.to_json}\n\ndata: [DONE]\n\n"]
  end

  private

  def body_json_from(request)
    req_body = request.body.read
    return {} if req_body.blank?
    JSON.parse(req_body)
  rescue JSON::ParserError => err
    puts "Failed to parse request body as JSON: #{err}"
    {}
  end

  def fake_copilot_message
    paragraphs = []
    (rand(3) + 1).times do
      paragraphs << Faker::Lorem.paragraph
    end
    paragraphs.join("\n\n")
  end

  def fake_diff_hunk
    {
      "type" => "diff-hunk",
      "changeReference" => "Ff3edeb9L81R81",
      "fileName" => "`#{Faker::File.file_name}`",
      "diff" => "```diff\n@@ -81,7 +81,7 @@ class Api::Staff::CopilotTrials \u003c Api::Staff::App\n   private\n \n   def find_trial(org)\n-    Copilot::BusinessTrial.for_organization(org)\n+    org.trial_for_copilot_business\n   end\n \n   def trial_eligibility_payload(org, copilot_plan)\n```\n",
      "headerContext" => " in `class Api::Staff::CopilotTrials \u003c Api::Staff::App`",
    }
  end

  def fake_reference
    diff_hunks = []
    (rand(10) + 1).times do
      diff_hunks << fake_diff_hunk
    end
    {
      "type" => "tree-comparison",
      "baseRevision" => SecureRandom.hex(20),
      "baseRepoId" => 3,
      "headRevision" => SecureRandom.hex(20),
      "headRepoId" => 3,
      "diffHunks" => diff_hunks,
    }
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  port = ARGV.first
  FauxpilotApiServer.set(:bind, "127.0.0.1")
  FauxpilotApiServer.set(:port, port) if port
  FauxpilotApiServer.run!
end
