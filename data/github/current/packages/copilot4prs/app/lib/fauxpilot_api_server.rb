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

  @copilot_agent_id = nil
  @test_agent_id = nil

  def self.copilot_agent_id
    @copilot_agent_id ||= Integration.find_by(slug: "copilot-swe-agent")&.id || 1143301
  end

  def self.test_agent_id
    @test_agent_id ||= Integration.find_by(slug: Apps::Privileged::CodexAgent::SLUG)&.id || 838
  end

  def self.set_agent_ids(copilot_id, test_id)
    @copilot_agent_id = copilot_id
    @test_agent_id = test_id
    puts "Updated agent IDs: Copilot=#{copilot_id}, Test=#{test_id}"
  end

  # https://github.com/github/copilot-api/blob/2787cbb60cd3cae232dd2e171af7ac5b273226fb/pkg/agent/handler.go#L64
  get "/agents/sessions/resources" do
    resources = JSON.parse(File.read("packages/copilot_sessions/app/mocks/resources_response.json")).dig("resources")
    cached_resources = GitHub.cache.get("copilot_swe_agent_resources") || []
    [200, {}, { "resources" => resources + cached_resources }.to_json]
  end

  # https://github.com/github/copilot-api/blob/fd1b5efec47c5a6d7c89ac41974d84d0740c743d/pkg/rest/openai/handler.go#L120
  get "/models" do
    models = [fake_default_model]
    rand(10).times { models << fake_default_model }
    custom_key_names = rand(1..5).times.map { fake_custom_key_name }
    owner_names_by_custom_key_name = custom_key_names.map { |key_name| [key_name, fake_org_or_enterprise_name] }.to_h
    rand(10).times do
      custom_key_name = custom_key_names.sample
      owner_name = owner_names_by_custom_key_name[custom_key_name]
      models << fake_custom_model(custom_key_name: custom_key_name, owner_name: owner_name)
    end
    [200, {}, { data: models, object: "list" }.to_json]
  end

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
    format_logs = format_session_logs(session_id)

    [200, { "Content-Type" => "text/event-stream" }, format_logs]
  end

  get "/agents/sessions/resource/:resource_type/:resource_id" do
    pull_id = params[:resource_id].to_i
    [200, {}, { sessions: user_sessions_for_pr(pull_id) }.to_json]
  end

  get "/agents/sessions/resource/:resource_type/:resource_id/inactive_logs" do
    pull_id = params[:resource_id].to_i
    inactive_user_sessions = user_sessions_for_pr(pull_id).select { |session| %w[completed cancelled failed].include?(session["state"]) }
    inactive_logs_hash = inactive_user_sessions.each_with_object({}) do |session, hash|
      hash[session["id"]] = format_session_logs(session["id"])
    end
    [200, {}, { logs: inactive_logs_hash }.to_json]
  end

  get "/agents/sessions" do
    [200, {}, { "sessions" => user_sessions }.to_json]
  end

  get "/agents/sessions/:session_id" do
    session_id = params[:session_id]
    session = sessions.find { |s| s["id"] == session_id }
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
    file_sessions = JSON.parse(File.read("packages/copilot_sessions/app/mocks/sessions_response.json"))&.dig("sessions")

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
    subagent = body_params["subagent"]
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
      title: title,
      body: generate_dynamic_pull_body
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
      "resource_global_id": pull.global_relay_id,
      "last_updated_at": Time.current,
      "created_at": Time.current,
      "completed_at": nil,
      "premium_requests": 1,
      "workflow_run_id": nil,
      "log_entries": [],
      "error": nil,
      "event_identifiers": event_identifiers,
      "event_type": "api_call_received",
      "subagent": subagent,
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
          "global_relay_id": pull.global_relay_id,
          "title": title,
          "body": pull.body,
      }
  }
    [200, {}, response.to_json]

  end

  # Versioned SWE agent endpoint (supports v0, v1, etc.)
  post "/agents/swe/:version/jobs/:owner/:name" do
    body_params = body_json_from(request)
    nwo = "#{params[:owner]}/#{params[:name]}"
    current_user = User.find_by(login: "monalisa")
    repo = Repository.nwo(nwo)
    problem_statement = body_params["problem_statement"] || Faker::Lorem.sentence(word_count: 10)
    event_identifiers = body_params["event_identifiers"]
    subagent = body_params["subagent"]
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
      title: title,
      body: generate_dynamic_pull_body
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
      "resource_global_id": pull.global_relay_id,
      "last_updated_at": Time.current,
      "created_at": Time.current,
      "completed_at": nil,
      "premium_requests": 1,
      "workflow_run_id": nil,
      "log_entries": [],
      "error": nil,
      "event_identifiers": event_identifiers,
      "event_type": "api_call_received",
      "subagent": subagent,
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
          "global_relay_id": pull.global_relay_id,
          "title": title,
          "body": pull.body,
      }
  }
    [200, {}, response.to_json]

  end

  get "/agents/swe/internal/subagents/:owner/:name" do
    owner = params[:owner]
    name = params[:name]

    # Return a fake list of agents for development/testing
    agents = [
      {
        "name" => "joker",
        "repo_owner" => owner,
        "repo_name" => name,
        "display_name" => "The Joker",
        "description" => "This agent generates jokes at the bottom of any md file it generates",
        "prompt" => "",
        "tools" => []
      },
      {
        "name" => "code-reviewer",
        "repo_owner" => owner,
        "repo_name" => name,
        "display_name" => "Code Reviewer",
        "description" => "Reviews code and provides feedback on best practices",
        "prompt" => "You are a helpful code reviewer",
        "tools" => %w[eslint rubocop]
      },
      {
        "name" => "test-generator",
        "repo_owner" => owner,
        "repo_name" => name,
        "display_name" => "Test Generator",
        "description" => "Generates comprehensive test cases for code",
        "prompt" => "Generate thorough test coverage",
        "tools" => %w[rspec jest]
      }
    ]

    [200, {}, { "agents" => agents }.to_json]
  end

  get "/agents/swe/custom-agents/:owner/:repo" do
    owner = params[:owner]
    repo = params[:repo]

    # Return a fake list of custom agents for development/testing
    agents = [
      {
        "name" => "custom-code-reviewer",
        "repo_owner" => owner,
        "repo_name" => repo,
        "display_name" => "Custom Code Reviewer",
        "description" => "Custom agent that reviews code and provides detailed feedback",
        "prompt" => "You are a specialized code reviewer for this repository",
        "tools" => %w[eslint rubocop prettier]
      },
      {
        "name" => "custom-bug-hunter",
        "repo_owner" => owner,
        "repo_name" => repo,
        "display_name" => "Bug Hunter",
        "description" => "Custom agent specialized in finding and fixing bugs",
        "prompt" => "You are an expert at identifying and fixing bugs",
        "tools" => %w[debugger logger]
      },
      {
        "name" => "custom-docs-writer",
        "repo_owner" => owner,
        "repo_name" => repo,
        "display_name" => "Documentation Writer",
        "description" => "Custom agent that generates comprehensive documentation",
        "prompt" => "You are a technical writer creating clear documentation",
        "tools" => %w[markdown asciidoc]
      }
    ]

    [200, {}, { "agents" => agents }.to_json]
  end

  # Mock endpoint for fetching tasks for a repository
  get "/owner/:owner/repo/:repo/tasks" do
    owner_login = params[:owner]
    repo_name = params[:repo]
    owner_filter = request.query_string.match(/owner=(\d+)/)&.captures&.first

    nwo = "#{owner_login}/#{repo_name}"
    repo = Repository.nwo(nwo)

    all_sessions = sessions
    repo_sessions = if repo
      all_sessions.select { |s| s["repo_id"] == repo.id }
    else
      all_sessions
    end

    if owner_filter.present?
      repo_sessions = repo_sessions.select { |s| s["user_id"].to_s == owner_filter.to_s }
    end

    tasks_by_resource = repo_sessions.group_by { |s| s["resource_id"] }

    tasks = tasks_by_resource.map do |_, resource_sessions|
      sorted_sessions = resource_sessions.sort_by { |s| s["last_updated_at"] || s["created_at"] }.reverse
      latest_session = sorted_sessions.first

      latest_session = attach_valid_objects(latest_session.dup)

      {
        "resource_type" => latest_session["resource_type"] || "pull",
        "resource_id" => latest_session["resource_id"],
        "resource_global_id" => latest_session["resource_global_id"],
        "session_count" => resource_sessions.size,
        "latest_session_updated_at" => latest_session["last_updated_at"],
        "last_updated_at" => latest_session["last_updated_at"],
        "latest_session_state" => latest_session["state"],
        "latest_session_id" => latest_session["id"],
        "event_identifiers" => latest_session["event_identifiers"],
        "event_type" => latest_session["event_type"],
        "current_user_can_push" => true
      }
    end

    tasks = tasks.sort_by { |t| t["last_updated_at"] || "" }.reverse

    [200, {}, { "tasks" => tasks }.to_json]
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
      "external_id" => SecureRandom.uuid, # Once a command is created, you can use this value in packages/copilot_swe_agent/app/mocks/session_logs_response.json -> "source" -> `command-{external_id}` to simulate user commands in logs.
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
    if stored_commands.empty?
      log_commands = JSON.parse(File.read("packages/copilot_sessions/app/mocks/commands_response.json")).dig("commands")
      GitHub.cache.set(commands_cache_key, log_commands)
    end

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

  def predefined_session_templates
    [
      { state: "failed", name: "Bug fix implementation", error: "Build failed due to missing dependencies" },
      { state: "waiting_for_user", name: "Feature enhancement", error: nil },
      { state: "in_progress", name: "Code refactoring and optimization", error: nil }
    ]
  end

  def predefined_session_ids
    predefined_session_templates.map.with_index { |template, i| "new-session-#{template[:state]}-#{i}" }
  end

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

  # Private: Returns a made up model name like "PDX-7.3" or "SLC-0.6-turbo".
  def fake_model_name
    family = Faker::Travel::Airport.iata(size: "large", region: "united_states") # e.g., "PDX", "SLC"
    version = "#{rand(10)}.#{rand(9)}" # e.g., "7.3", "0.6"
    suffix = if [true, false, false, false].sample # less likely to have a suffix
      %w(-turbo -turbo-instruct -mini -small -nano).sample
    else
      ""
    end
    "#{family}-#{version}#{suffix}"
  end

  def fake_default_model
    model_name = fake_model_name
    model_id = model_name.downcase
    version_date = (Date.current - rand(1..300).days).strftime("%Y-%m-%d")
    is_premium = [true, false].sample
    billing_multiplier = is_premium ? rand(0.0..0.5) : 0
    {
      billing: { is_premium: is_premium, multiplier: billing_multiplier },
      capabilities: {
        family: model_id,
        limits: {
          max_context_window_tokens: rand(100_000..150_000),
          max_output_tokens: rand(10_000..20_000),
          max_prompt_tokens: rand(100_000..150_000),
          vision: {
            max_prompt_image_size: rand(3_000_000..3_200_000),
            max_prompt_images: 1,
            supported_media_types: %w(image/jpeg image/png image/webp image/gif),
          },
        },
        object: "model_capabilities",
        supports: {
          parallel_tool_calls: true,
          streaming: true,
          structured_outputs: true,
          tool_calls: true,
          vision: true
        },
        tokenizer: "o200k_base",
        type: "chat"
      },
      id: model_id,
      is_chat_default: true,
      is_chat_fallback: true,
      model_picker_category: %w(versatile lightweight powerful).sample,
      model_picker_enabled: true,
      name: model_name,
      object: "model",
      policy: {
        state: "enabled",
        terms: "Enable access to the latest #{model_name} model from OpenAI."
      },
      preview: false,
      vendor: "Azure OpenAI",
      version: "#{model_name}-#{version_date}",
    }
  end

  # Private: Returns a plausible name for a CopilotByok::CustomKey record.
  def fake_custom_key_name
    "My_#{Faker::Emotion.adjective.capitalize}_Custom_Key"
  end

  def fake_custom_model(custom_key_name: nil, owner_name: nil)
    model_id = fake_model_name.downcase
    custom_key_name ||= fake_custom_key_name
    owner_name ||= fake_org_or_enterprise_name
    {
      billing: { is_premium: false, multiplier: 0 }, # Bring Your Own Key models are never billed
      capabilities: {
        family: "custom",
        limits: {
          max_context_window_tokens: 90000,
          max_output_tokens: 8192,
          max_prompt_tokens: 64000
        },
        object: "model_capabilities",
        supports: {},
        tokenizer: "cl100k_base",
        type: "chat",
      },
      custom_model: {
        key_name: custom_key_name,
        owner_name: owner_name,
      },
      id: "custom/#{custom_key_name}/#{model_id}",
      is_chat_default: false,
      is_chat_fallback: false,
      model_picker_enabled: true,
      name: "#{model_id} · #{custom_key_name}",
      object: "model",
      preview: false,
      supported_endpoints: %w(/chat/completions),
      vendor: "openai",
      version: ""
    }
  end

  def fake_org_or_enterprise_name
    result = "#{Faker::Adjective.positive}-#{Faker::Appliance.equipment}"
    # Strip out characters that wouldn't show up in an organization login:
    result.downcase.gsub(/\s+/, "-").gsub(/[^[a-z0-9\-_]]/, "")
  end

  def attach_valid_objects(session)
    # Attempt to use the real pull if it exists
    found_pull = PullRequest.find_by(id: session["resource_id"])
    pull_to_use = found_pull

    if pull_to_use.nil?
      cached_pull_id = GitHub.cache.get("copilot_swe_agent_map_resource_id#{session['resource_id']}")
      pull_to_use = PullRequest.find_by(id: cached_pull_id) if cached_pull_id
    end

    # Create a pull in a repo if one doesn't already exist to ensure we always have a global_relay_id we can use
    if pull_to_use.nil?
      user = User.find_by(login: "monalisa")
      repo = Repository.nwo("monalisa/smile")

      branch_name = "task-session-branch-#{SecureRandom.hex(8)}"

      # Get base branch
      base_ref = repo.heads.find_or_build(repo.default_branch)

      # Create new branch
      head_ref = repo.heads.create(branch_name, base_ref.target, user)

      # Add a commit to the branch
      head_ref.append_commit({ message: "Task session changes", committer: user }, user) do |files|
        files.add("task_file.md", "# Task 1\n\nThis is a task session file.")
        files.add("config/task_config_1.yml", "task_id: 1\nstatus: active")
      end

      pull_to_use = PullRequest.create_for!(
        repo,
        user:,
        base: repo.default_branch,
        head: branch_name,
        title: Faker::Lorem.sentence,
        body: generate_dynamic_pull_body,
      )
      GitHub.cache.set("copilot_swe_agent_map_resource_id#{session['resource_id']}", pull_to_use.id)
    else
      # Update the body of existing pull request every time it's accessed
      update_pull_request_body(pull_to_use)
      # Reload the pull request to ensure we have the updated data
      pull_to_use.reload
    end
    session.merge!("resource_global_id" => pull_to_use.global_relay_id, "resource_id" => pull_to_use.id)

    # If not the initial implementation, subsequent sessions should have valid comments attached to them
    if session["name"] != "Initial implementation"
      # Check if there are any comments mentioning Copilot already
      existing_comments = pull_to_use.issue.comments.where("compressed_body LIKE ?", "%@copilot%")
      comment = nil
      if existing_comments.any?
        comment = existing_comments.first
      else
        comment = pull_to_use.issue.create_comment(pull_to_use.user, "@copilot actually, do something else instead")
      end

      # Use the comment ID to simulate event_identifiers and event_type for the session
      session.merge!("event_identifiers" => [comment.id.to_s])
      session.merge!("event_type" => "pull_request_comment")
    end

    session
  end

  def sessions
    sessions = JSON.parse(File.read("packages/copilot_sessions/app/mocks/sessions_response.json"))&.dig("sessions")
    sessions = sessions.map do |session|
      # Replace agent IDs used in session response with the local agent ids to make sure they match for grabbing agent info
      if session["agent_id"] == 1143301
        session["agent_id"] = self.class.copilot_agent_id
      elsif session["agent_id"] == 838
        session["agent_id"] = self.class.test_agent_id
      end

      # Ensure repo_id is valid - if not, use monalisa/smile's repo id
      if session["repo_id"] && !Repository.find_by(id: session["repo_id"])
        smile_repo = Repository.nwo("monalisa/smile")
        session["repo_id"] = smile_repo.id if smile_repo
      end

      attach_valid_objects(session)
    end

    cached_sessions = GitHub.cache.get("copilot_swe_agent_sessions") || []
    sessions + cached_sessions
  end

  def user_sessions
    current_user = User.find_by(login: "monalisa")

    sessions.select do |session|
      simplified_session = session.transform_keys(&:to_sym)
      simplified_session[:user_id].to_i == current_user&.id
    end
  end

  def user_sessions_for_pr(pull_id)
    user_sessions.select do |session|
      simplified_session = session.transform_keys(&:to_sym)
      simplified_session[:resource_id].to_i == pull_id
    end
  end

  def format_session_logs(session_id)
    # Get base logs from file
    logs = JSON.parse(File.read("packages/copilot_sessions/app/mocks/session_logs_response.json")).dig("results") || []

    # Get any cached steering comments for this session
    cache_key = "session_logs_#{session_id}"
    cached_logs = GitHub.cache.get(cache_key) || []

    # Combine file logs with cached steering comments
    all_logs = logs + cached_logs

    "data: #{all_logs.map(&:to_json).join("\n\ndata: ")}\n\ndata: [DONE]\n\n"
  end

  def generate_dynamic_pull_body
    timestamp = Time.current.strftime("%Y-%m-%d %H:%M:%S UTC")
    revision_count = rand(1..10)

    body_content = [
      "## Pull request summary",
      "",
      "This pull request has been dynamically updated.",
      "",
      "**Last updated:** #{timestamp}",
      "**Revision count:** #{revision_count}",
      "",
      "",
      "---",
      "*This body was auto-generated at #{timestamp} for development/testing purposes.*"
    ]

    body_content.join("\n")
  end

  def pull_request_has_revisions?(pull_request)
    pull_request.issue.user_content_edits.any?
  rescue => e
    Rails.logger.error "Failed to check revisions for PR #{pull_request.id}: #{e.message}"
    false
  end

  def update_pull_request_body(pull_request)
    # Only update the body if it hasn't had any revisions yet
    return if pull_request_has_revisions?(pull_request)

    new_body = generate_dynamic_pull_body
    current_user = User.find_by(login: "monalisa")
    pull_request.issue.update_body(new_body, current_user)
  rescue => e
    Rails.logger.error "Failed to update PR #{pull_request.id} body: #{e.message}"
    Rails.logger.error (e.backtrace || []).join("\n")
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  port = ARGV.first
  FauxpilotApiServer.set(:bind, "127.0.0.1")
  FauxpilotApiServer.set(:port, port) if port
  FauxpilotApiServer.run!
end
