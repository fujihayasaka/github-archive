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
    allowed_origins = ["http://github.localhost", "http://127.0.0.1"]
    request_origin = request.env["HTTP_ORIGIN"]
    if allowed_origins.include?(request_origin)
      headers "Access-Control-Allow-Origin" => request_origin
    end
    headers "Access-Control-Allow-Headers" => "Content-Type,Authorization"
    headers "Access-Control-Allow-Methods" => "GET, POST, OPTIONS"
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

  get "/agents/sessions/:session_id/logs" do
    session_id = params[:session_id]

    # Get base logs from file
    logs = JSON.parse(File.read("packages/copilot_swe_agent/app/mocks/session_logs_response.json")).dig("results") || []

    # Get any cached steering comments for this session
    cache_key = "session_logs_#{session_id}"
    cached_logs = GitHub.cache.get(cache_key) || []

    # Combine file logs with cached steering comments
    all_logs = logs + cached_logs

    [200, { "Content-Type" => "text/event-stream" }, "data: #{all_logs.map(&:to_json).join("\n\ndata: ")}\n\ndata: [DONE]\n\n"]
  end

  get "/agents/sessions/resource/:resource_type/:resource_id" do
    pull_id = params[:resource_id].to_i
    sessions = JSON.parse(File.read("packages/copilot_swe_agent/app/mocks/sessions_response.json"))&.dig("sessions")
    cached_sessions = GitHub.cache.get("copilot_swe_agent_sessions") || []

    [200, {}, { sessions: (sessions + cached_sessions).select { |session| session.transform_keys(&:to_sym)[:resource_id].to_i == pull_id } }.to_json]
  end

  get "/agents/sessions" do
    sessions = JSON.parse(File.read("packages/copilot_swe_agent/app/mocks/sessions_response.json")).dig("sessions")
    cached_sessions = GitHub.cache.get("copilot_swe_agent_sessions") || []
    [200, {}, { "sessions" => sessions + cached_sessions }.to_json]
  end

  get "/agents/sessions/:session_id" do
    session_id = params[:session_id]
    sessions = JSON.parse(File.read("packages/copilot_swe_agent/app/mocks/sessions_response.json")).dig("sessions")
    cached_sessions = GitHub.cache.get("copilot_swe_agent_sessions") || []
    all_sessions = sessions + cached_sessions
    session = all_sessions.find { |s| s["id"] == session_id }
    if session
      [200, {}, session.to_json]
    else
      [404, { "Content-Type" => "application/json" }, { "error" => "Session with ID #{session_id} not found" }.to_json]
    end
  end

  # mock endpoint for stop session
  post "/agents/swe/jobs/:owner/:name/session/:session_id/cancel" do
    body_params = body_json_from(request)
    session_id = params[:session_id]
    nwo = "#{params[:owner]}/#{params[:name]}"

    # Check user permissions
    current_user = User.find_by(login: "monalisa")
    repo = Repository.nwo(nwo)

    # Mock permission check - in real app this would check if user can push to the repo
    can_push = current_user && repo && repo.pushable_by?(current_user)

    # Find and update the session state in cache
    cache_key = "copilot_swe_agent_sessions"
    cached_sessions = GitHub.cache.get(cache_key) || []
    file_sessions = JSON.parse(File.read("packages/copilot_swe_agent/app/mocks/sessions_response.json"))&.dig("sessions")

    # Find the session to stop from cache and file
    session_to_stop = cached_sessions.find { |session| session["id"] == session_id }
    is_cached_session = true

    if !session_to_stop
      session_to_stop = file_sessions.find { |session| session["id"] == session_id }
      is_cached_session = false
    end

    # Check if session is in a stoppable state
    stoppable_states = %w[in_progress idle waiting_for_user]

    if can_push && session_to_stop && stoppable_states.include?(session_to_stop["state"])
      # Update session state to cancelled
      session_to_stop["state"] = "cancelled"
      session_to_stop["completed_at"] = Time.current
      session_to_stop["last_updated_at"] = Time.current

      # Update the cache
      GitHub.cache.set(cache_key, cached_sessions)

      response = {
        "session_id" => session_id,
        "state" => "cancelled",
        "updated_at" => session_to_stop["last_updated_at"]
      }

      [200, {}, response.to_json]
    else
      if !can_push
        [403, { "Content-Type" => "application/json" }, { error: "You do not have permission to stop this session" }.to_json]
      elsif !session_to_stop
        [404, { "Content-Type" => "application/json" }, { error: "Session with ID #{session_id} not found" }.to_json]
      else
        [400, { "Content-Type" => "application/json" }, { error: "Session state (#{session_to_stop['state']}) cannot be stopped" }.to_json]
      end
    end
  end

  # Fake endpoint for SWE agent session creation
  # This endpoint is hit by create_swe_agent_session in packages/copilot/app/models/copilot/user/copilot_api.rb
  post "/agents/swe/jobs/:owner/:name" do
    body_params = body_json_from(request)
    nwo = "#{params[:owner]}/#{params[:name]}"
    current_user = User.find_by(login: "monalisa")
    repo = Repository.nwo(nwo)
    problem_statement = body_params["problem_statement"] || Faker::Lorem.sentence(word_count: 10)
    event_identifiers = body_params["event_identifiers"]
    branch_name = SecureRandom.uuid
    base_ref_name = body_params.dig("pull_request", "base_ref") || repo.default_branch
    base_ref = repo.heads.find_or_build(base_ref_name)
    head_ref = repo.heads.create(branch_name, base_ref.target, current_user)
    head_ref.append_commit({ message: "copilot changes", committer: current_user }, current_user) do |files|
      files.add("README.md", "foo")
      files.add("config/gitconfig", "foo")
    end
    sleep(3)

    # Extract title from pull_request data if provided, otherwise use problem_statement with [WIP] prefix
    title = body_params.dig("pull_request", "title") || "[WIP] #{problem_statement}"

    pull = PullRequest.create_for!(
      repo,
      user: current_user,
      base: "main",
      head: branch_name,
      title: title
    )

    new_session = {
      "id": SecureRandom.uuid,
      "name": problem_statement,
      "user_id": current_user&.id,
      "agent_id": 1143301,
      "state": "in_progress",
      "logs": "",
      "owner_id": 9919,
      "repo_id": repo.id,
      "resource_type": "pull",
      "resource_id": pull.id,
      "last_updated_at": Time.current,
      "created_at": Time.current,
      "completed_at": nil,
      "premium_requests": 1,
      "workflow_run_id": nil,
      "log_entries": [],
      "error": nil,
      "event_identifiers": event_identifiers,
      "event_type": "api_call_received",
    }
    cache_key = "copilot_swe_agent_sessions"
    sessions = GitHub.cache.get(cache_key) || []
    sessions << new_session
    GitHub.cache.set(cache_key, sessions)
    # Create pull request
    response = {
      "session_id": new_session[:id],
      "updated_at": new_session[:last_updated_at],
      "pull_request": {
          # TODO: Add more pull request data to better replicate production
          "id": pull.id,
          "title": title,
      }
  }
    [200, {}, response.to_json]

  end

  # Mock endpoint for steering comments (SessionContent fetchCAPI)
  post "/agents/sessions/:session_id/commands" do
    body_params = body_json_from(request)
    session_id = params[:session_id]
    content = body_params["content"]

    # Validate required content parameter
    if content&.strip&.empty?
      return [400, { "Content-Type" => "application/json" }, { error: "Content parameter is required and cannot be empty" }.to_json]
    end

    # Store the command in memory for the GET endpoint to return
    command_id = SecureRandom.uuid
    new_command = {
      "id" => command_id,
      "user_id" => 42, # Mock user ID
      "session_id" => session_id,
      "content" => content,
      "created_at" => Time.current.iso8601,
      "updated_at" => Time.current.iso8601,
      "state" => "queued", # Start as queued
      "error" => T.let(nil, T.nilable(String))
    }

    # Store in session-specific commands cache
    commands_cache_key = "session_commands_#{session_id}"
    existing_commands = GitHub.cache.get(commands_cache_key) || []
    existing_commands << new_command
    GitHub.cache.set(commands_cache_key, existing_commands)


    response = {
      "command_id" => command_id,
    }
    [201, {}, response.to_json]
  end

  # Mock endpoint for fetching commands (SessionContent useListCommands)
  get "/agents/sessions/:session_id/commands" do
    session_id = params[:session_id]
    state_filter = params[:state] # e.g., "queued,failed"

    # Get stored commands from cache
    commands_cache_key = "session_commands_#{session_id}"
    stored_commands = GitHub.cache.get(commands_cache_key) || []

    # Update command states based on time (simple local dev simulation)
    commands = update_command_states(stored_commands, commands_cache_key)

    # Filter by state if provided
    if state_filter.present?
      allowed_states = state_filter.split(",").map(&:strip)
      commands = commands.select { |cmd| allowed_states.include?(cmd["state"]) }
    end

    response = {
      "commands" => commands
    }
    [200, {}, response.to_json]
  end

  private

  def update_command_states(commands, commands_cache_key)
    updated_commands = commands.map do |cmd|
      # Only update queued commands
      if cmd["state"] == "queued"
        created_at = Time.parse(cmd["created_at"])
        # After 5 seconds, mark as completed
        if Time.current - created_at > 5.seconds
          cmd.merge({
            "state" => "completed",
            "updated_at" => Time.current.iso8601,
            "error" => nil
          })
        else
          cmd
        end
      else
        cmd
      end
    end

    # Update cache if any commands were updated
    unless updated_commands == commands
      GitHub.cache.set(commands_cache_key, updated_commands)
    end

    updated_commands
  end

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
