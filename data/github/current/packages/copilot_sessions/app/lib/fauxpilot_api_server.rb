# typed: true
# frozen_string_literal: true

require "sinatra/base"
require "set"
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

  SESSIONS_CACHE_KEY = "copilot_swe_agent_sessions"
  TASKS_CACHE_KEY = "copilot_swe_agent_tasks"
  TASKS_INITIALIZED_KEY = "copilot_tasks_initialized"

  @copilot_agent_id = nil
  @test_agent_id = nil
  @base_sessions = nil
  @base_tasks = nil

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

  # Load base sessions from JSON file (cached in class variable)
  def self.base_sessions
    @base_sessions ||= JSON.parse(File.read("packages/copilot_sessions/app/mocks/sessions_response.json"))&.dig("sessions") || []
  end

  # Get all sessions - base sessions plus any cached new sessions
  def self.all_sessions
    cached_sessions = GitHub.cache.get(SESSIONS_CACHE_KEY) || []
    cached_session_ids = cached_sessions.map { |s| s["id"] }.to_set

    # Combine base sessions (excluding any that are also in cache) with cached sessions
    combined = base_sessions.reject { |s| cached_session_ids.include?(s["id"]) } + cached_sessions
    combined
  end

  # Add a new session to the cache
  def self.add_session(session)
    cached_sessions = GitHub.cache.get(SESSIONS_CACHE_KEY) || []
    cached_sessions << session
    GitHub.cache.set(SESSIONS_CACHE_KEY, cached_sessions)
  end

  # Update a session in the cache (for base sessions, copies them to cache first)
  def self.update_session(session_id, updates)
    cached_sessions = GitHub.cache.get(SESSIONS_CACHE_KEY) || []
    session_in_cache = cached_sessions.find { |s| s["id"] == session_id }

    if session_in_cache
      # Update the session in cache
      session_in_cache.merge!(updates)
      GitHub.cache.set(SESSIONS_CACHE_KEY, cached_sessions)
      session_in_cache
    else
      # Check if it's a base session, if so copy to cache with updates
      base_session = base_sessions.find { |s| s["id"] == session_id }
      if base_session
        updated_session = base_session.dup.merge(updates)
        cached_sessions << updated_session
        GitHub.cache.set(SESSIONS_CACHE_KEY, cached_sessions)
        updated_session
      end
    end
  end

  def self.reset_sessions_cache
    @base_sessions = nil
    GitHub.cache.delete(SESSIONS_CACHE_KEY)
  end

  # Load base tasks from JSON file (cached in class variable)
  def self.base_tasks
    @base_tasks ||= JSON.parse(File.read("packages/copilot_sessions/app/mocks/tasks_response.json"))&.dig("tasks") || []
  end

  # Get all tasks - base tasks plus any cached new tasks
  # Also ensures task artifact PRs exist on first access
  def self.all_tasks
    ensure_task_artifacts_exist
    cached_tasks = GitHub.cache.get(TASKS_CACHE_KEY) || []
    cached_task_ids = cached_tasks.map { |t| t["id"] }.to_set

    # Combine base tasks (excluding any that are also in cache) with cached tasks
    combined = base_tasks.reject { |t| cached_task_ids.include?(t["id"]) } + cached_tasks
    combined
  end

  # Add a new task to the cache
  def self.add_task(task)
    cached_tasks = GitHub.cache.get(TASKS_CACHE_KEY) || []
    cached_tasks << task
    GitHub.cache.set(TASKS_CACHE_KEY, cached_tasks)
  end

  # Update a task in the cache (for base tasks, copies them to cache first)
  def self.update_task(task_id, updates)
    cached_tasks = GitHub.cache.get(TASKS_CACHE_KEY) || []
    task_in_cache = cached_tasks.find { |t| t["id"] == task_id }

    if task_in_cache
      task_in_cache.merge!(updates)
      GitHub.cache.set(TASKS_CACHE_KEY, cached_tasks)
      task_in_cache
    else
      base_task = base_tasks.find { |t| t["id"] == task_id }
      if base_task
        updated_task = base_task.dup.merge(updates)
        cached_tasks << updated_task
        GitHub.cache.set(TASKS_CACHE_KEY, cached_tasks)
        updated_task
      end
    end
  end

  # Find a task by ID from all tasks (base + cached)
  def self.find_task(task_id)
    all_tasks.find { |t| t["id"] == task_id }
  end

  def self.reset_tasks_cache
    @base_tasks = nil
    GitHub.cache.delete(TASKS_CACHE_KEY)
    GitHub.cache.delete(TASKS_INITIALIZED_KEY)
  end

  # Reset all caches (sessions and tasks)
  def self.reset_all_caches
    reset_sessions_cache
    reset_tasks_cache
  end

  # Ensure all task artifact PRs exist - runs once on first access
  def self.ensure_task_artifacts_exist
    return if GitHub.cache.get(TASKS_INITIALIZED_KEY)

    user = User.find_by(login: "monalisa")
    return unless user

    base_tasks.each do |task|
      task["artifacts"]&.each do |artifact|
        next unless artifact["provider"] == "github" && artifact.dig("data", "type") == "pull"

        pr_id = artifact.dig("data", "id")
        next unless pr_id

        # Check if PR exists
        existing_pr = PullRequest.find_by(id: pr_id)
        next if existing_pr # PR already exists, nothing to do

        # PR doesn't exist - create a mock one
        repo = Repository.find_by(id: task.dig("repository", "id"))
        # Fall back to monalisa/smile if repo not found
        repo ||= Repository.nwo("monalisa/smile")
        next unless repo

        creator = User.find_by(id: task.dig("creator", "id")) || user
        new_pr = create_pr_for_task(repo, creator, task)
        next unless new_pr

        # Update the task's artifact with the real PR ID
        artifact["data"]["id"] = new_pr.id
        artifact["data"]["global_id"] = new_pr.global_relay_id

        # Also update any sessions that reference this task
        update_sessions_for_task(task["id"], new_pr)
      end
    end

    GitHub.cache.set(TASKS_INITIALIZED_KEY, true)
  rescue StandardError => e
    # Log but don't fail - tasks will just have invalid PR references
    puts "Failed to ensure task artifacts exist: #{e.message}"
  end

  # Create a PR for a task that doesn't have one
  def self.create_pr_for_task(repo, user, task)
    branch_name = "copilot-task-#{task['id'][0..7]}-#{SecureRandom.hex(4)}"
    base_ref = repo.heads.find_or_build(repo.default_branch)
    head_ref = repo.heads.create(branch_name, base_ref.target, user)

    head_ref.append_commit({ message: "Copilot agent changes", committer: user }, user) do |files|
      files.add("README.md", "# Task #{task['id']}\n\nGenerated by Copilot agent")
    end

    PullRequest.create_for!(
      repo,
      user: user,
      base: repo.default_branch,
      head: branch_name,
      title: "[Copilot] Task #{task['id'][0..7]}",
      body: "Mock PR for local development testing. Task ID: #{task['id']}"
    )
  rescue StandardError => e
    puts "Failed to create PR for task #{task['id']}: #{e.message}"
    nil
  end

  # Update sessions that reference a task with the new PR info
  def self.update_sessions_for_task(task_id, pr)
    # Update base sessions in memory
    base_sessions.each do |session|
      next unless session["task_id"] == task_id
      session["resource_id"] = pr.id
      session["resource_global_id"] = pr.global_relay_id
    end

    # Update cached sessions
    cached_sessions = GitHub.cache.get(SESSIONS_CACHE_KEY) || []
    updated = cached_sessions.any? do |session|
      next false unless session["task_id"] == task_id
      session["resource_id"] = pr.id
      session["resource_global_id"] = pr.global_relay_id
      true
    end
    GitHub.cache.set(SESSIONS_CACHE_KEY, cached_sessions) if updated
  end

  # https://github.com/github/copilot-api/blob/2787cbb60cd3cae232dd2e171af7ac5b273226fb/pkg/agent/handler.go#L64
  get "/agents/sessions/resources" do
    resources = JSON.parse(File.read("packages/copilot_sessions/app/mocks/resources_response.json")).dig("resources")
    cached_resources = GitHub.cache.get("copilot_swe_agent_resources") || []
    [200, {}, { "resources" => resources + cached_resources }.to_json]
  end

  # https://github.com/github/copilot-api/blob/fd1b5efec47c5a6d7c89ac41974d84d0740c743d/pkg/rest/openai/handler.go#L120
  get "/models" do
    # Add specific well-known models for testing
    known_models = [
      { id: "claude-sonnet-4.5", name: "Claude Sonnet 4.5", vendor: "Anthropic", icon: "https://github.githubassets.com/assets/anthropic-logo-a88b8e95.svg" },
      { id: "claude-opus-4.5", name: "Claude Opus 4.5", vendor: "Anthropic", icon: "https://github.githubassets.com/assets/anthropic-logo-a88b8e95.svg" },
      { id: "gpt-5.1-codex-max", name: "GPT-5.1-Codex-Max", vendor: "Azure OpenAI", icon: "https://github.githubassets.com/assets/openai-logo-d0dfc62e.svg" },
    ].map do |m|
      {
        billing: { is_premium: true, multiplier: rand(0.1..0.5).round(2) },
        capabilities: {
          family: m[:id],
          limits: { max_context_window_tokens: 128000, max_output_tokens: 16000, max_prompt_tokens: 128000 },
          object: "model_capabilities",
          supports: { parallel_tool_calls: true, streaming: true, tool_calls: true },
          type: "chat"
        },
        id: m[:id],
        is_chat_default: m[:id] == "claude-sonnet-4.5",
        model_picker_category: m[:id].include?("opus") || m[:id].include?("max") ? "powerful" : "versatile",
        model_picker_enabled: true,
        name: m[:name],
        object: "model",
        policy: { state: "enabled" },
        vendor: m[:vendor],
        icon: m[:icon],
      }
    end

    models = known_models
    rand(5).times { models << fake_default_model }
    custom_key_names = rand(1..3).times.map { fake_custom_key_name }
    owner_names_by_custom_key_name = custom_key_names.map { |key_name| [key_name, fake_org_or_enterprise_name] }.to_h
    rand(3).times do
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

  post "/agents/github-notifications-digest" do
    body = JSON.parse(request.body.read)
    messages = body["messages"] || []
    user_message = messages.find { |m| m["role"] == "user" }

    notifications = []
    if user_message && user_message["content"].present?
      begin
        payload = JSON.parse(user_message["content"])
        notifications = payload["copilot_notifications"] || []
      rescue JSON::ParserError
        # fall through with empty notifications
      end
    end

    mock_items = notifications.each_with_index.map do |notification, index|
      subject_type = notification.dig("subject", "type").to_s
      category, priority, summary, recommendation, ctas = mock_notification_digest_item(subject_type, index)

      {
        "id" => notification["id"],
        "category" => category,
        "priority" => priority,
        "recommendation" => recommendation,
        "summary" => summary,
        "ctas" => ctas,
      }
    end

    notification_count = notifications.size
    category_count = mock_items.map { |h| h["category"] }.uniq.size
    digest_summary = "You have #{notification_count} #{"notification".pluralize(notification_count)} across #{category_count} #{"category".pluralize(category_count)}."

    digest_content = {
      "digest_summary" => digest_summary,
      "items" => mock_items,
    }.to_json

    data = {
      "choices": [
        {
          "finish_reason": "stop",
          "index": 0,
          "message": {
            "content": digest_content,
            "role": "assistant"
          }
        }
      ],
      "created": Time.now.to_i,
      "id": "chatcmpl-notifications-digest-#{SecureRandom.hex(8)}",
      "usage": {
        "completion_tokens": 200,
        "prompt_tokens": 500,
        "total_tokens": 700
      }
    }

    [200, { "Content-Type" => "application/json" }, data.to_json]
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

  # Models endpoint for coding agent model picker
  get "/agents/swe/models" do
    models = [
      {
        "id" => "auto",
        "name" => "Auto",
        "description" => "Let Copilot choose the best model",
        "vendor" => "GitHub",
        "object" => "model",
        "auto" => true,
        "model_picker_enabled" => true,
        "model_picker_category" => "versatile",
        "billing" => {
          "multiplier" => 1.0
        },
        "capabilities" => {
          "type" => "chat"
        }
      },
      {
        "id" => "claude-sonnet-4.5",
        "name" => "Claude Sonnet 4.5",
        "description" => "Anthropic's fast and efficient model",
        "vendor" => "anthropic",
        "object" => "model",
        "model_picker_enabled" => true,
        "model_picker_category" => "versatile",
        "billing" => {
          "multiplier" => 1.0
        },
        "capabilities" => {
          "type" => "chat"
        }
      },
      {
        "id" => "gpt-5.1-codex-max",
        "name" => "GPT-5.1-Codex-Max",
        "description" => "OpenAI's advanced reasoning model",
        "vendor" => "openai",
        "object" => "model",
        "model_picker_enabled" => true,
        "model_picker_category" => "powerful",
        "billing" => {
          "multiplier" => 2.0
        },
        "capabilities" => {
          "type" => "chat"
        }
      },
      {
        "id" => "claude-opus-4.5",
        "name" => "Claude Opus 4.5",
        "description" => "Anthropic's most capable model",
        "vendor" => "anthropic",
        "object" => "model",
        "model_picker_enabled" => true,
        "model_picker_category" => "powerful",
        "billing" => {
          "multiplier" => 3.0
        },
        "capabilities" => {
          "type" => "chat"
        }
      }
    ]

    [200, {}, { "data" => models, "object" => "list" }.to_json]
  end

  get "/agents/repos/:owner/:repo/tasks/:task_id/inactive_logs" do
    task_id = params[:task_id]
    task_sessions = sessions.select { |session| session["task_id"] == task_id }
    inactive_task_sessions = task_sessions.select { |session| %w[completed cancelled failed].include?(session["state"]) }
    inactive_logs_hash = inactive_task_sessions.each_with_object({}) do |session, hash|
      hash[session["id"]] = format_session_logs(session["id"])
    end
    [200, {}, { logs: inactive_logs_hash }.to_json]
  end

  get "/agents/sessions" do
    filtered_sessions = user_sessions

    if params[:event_identifiers].present?
      identifiers = params[:event_identifiers].split(",")
      filtered_sessions = filtered_sessions.select do |session|
        session_identifiers = session["event_identifiers"] || []
        identifiers.any? { |id| session_identifiers.include?(id) }
      end
    end

    [200, {}, { "sessions" => filtered_sessions }.to_json]
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

    # Find the session to stop from all sessions (base + cached)
    all_sessions = self.class.all_sessions
    session_to_stop = all_sessions.find { |session| session["id"] == session_id }

    # Check if session is in a stoppable state
    stoppable_states = %w[in_progress idle waiting_for_user]

    if can_push && session_to_stop && stoppable_states.include?(session_to_stop["state"])
      # Update session state to cancelled
      updates = {
        "state" => "cancelled",
        "completed_at" => Time.current,
        "last_updated_at" => Time.current
      }
      updated_session = self.class.update_session(session_id, updates)

      # Search the session ID field of the cached tasks to find any tasks associated with this session
      associated_task = self.class.find_task(session_to_stop["task_id"])
      if associated_task
        # Update the session state in the task's sessions as well
        task_sessions = associated_task["sessions"] || []
        task_session = task_sessions.find { |s| s["id"] == session_id }
        if task_session
          task_session["state"] = "cancelled"
          task_session["completed_at"] = Time.current
          task_session["last_updated_at"] = Time.current
          self.class.update_task(associated_task["id"], { "sessions" => task_sessions, "status" => "cancelled" })
        end
      end

      response = {
        "session_id" => session_id,
        "state" => "cancelled",
        "updated_at" => updated_session["last_updated_at"]
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
      "id" => SecureRandom.uuid,
      "name" => problem_statement,
      "user" => { "id" => current_user&.id },
      "agent_id" => 1143301,
      "model" => "claude-sonnet-4.5",
      "state" => "in_progress",
      "logs" => "",
      "owner" => { "id" => 9919 },
      "repository" => { "id" => repo.id },
      "resource_type" => "pull",
      "resource_id" => pull.id,
      "resource_global_id" => pull.global_relay_id,
      "task_id" => SecureRandom.uuid,
      "last_updated_at" => Time.current,
      "created_at" => Time.current,
      "completed_at" => nil,
      "premium_requests" => 1,
      "workflow_run_id" => nil,
      "log_entries" => [],
      "error" => nil,
      "event_identifiers" => event_identifiers,
      "event_type" => "api_call_received",
      "subagent" => subagent,
      "event_content" => problem_statement,
    }
    self.class.add_session(new_session)
    # Create pull request
    response = {
      "session_id" => new_session["id"],
      "updated_at" => new_session["last_updated_at"],
      "pull_request" => {
          # TODO: Add more pull request data to better replicate production
          "id" => pull.id,
          "global_relay_id" => pull.global_relay_id,
          "title" => title,
          "body" => pull.body,
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
      "id" => SecureRandom.uuid,
      "name" => problem_statement,
      "user" => { "id" => current_user&.id },
      "agent_id" => 1143301,
      "model" => "claude-sonnet-4.5",
      "state" => "in_progress",
      "logs" => "",
      "owner" => { "id" => 9919 },
      "repository" => { "id" => repo.id },
      "resource_type" => "pull",
      "resource_id" => pull.id,
      "resource_global_id" => pull.global_relay_id,
      "task_id" => SecureRandom.uuid,
      "last_updated_at" => Time.current,
      "created_at" => Time.current,
      "completed_at" => nil,
      "premium_requests" => 1,
      "workflow_run_id" => nil,
      "log_entries" => [],
      "error" => nil,
      "event_identifiers" => event_identifiers,
      "event_type" => "api_call_received",
      "subagent" => subagent,
      "event_content" => problem_statement,
    }
    self.class.add_session(new_session)
    # Create pull request
    response = {
      "session_id" => new_session["id"],
      "updated_at" => new_session["last_updated_at"],
      "pull_request" => {
          # TODO: Add more pull request data to better replicate production
          "id" => pull.id,
          "global_relay_id" => pull.global_relay_id,
          "title" => title,
          "body" => pull.body,
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

  get "/agents/swe/models" do
    models = JSON.parse(File.read("packages/copilot_sessions/app/mocks/models_response.json"))
    [200, {}, models.to_json]
  end

  # Mock endpoint for fetching tasks by multiple IDs in a single batch request
  get "/agents/tasks/batch" do
    task_ids = (params[:task_ids] || "").split(",").map(&:strip).reject(&:empty?)

    return [400, {}, { "error" => "task_ids parameter is required" }.to_json] if task_ids.empty?

    task_ids_set = task_ids.to_set
    tasks = self.class.all_tasks.select { |t| task_ids_set.include?(t["id"]) }

    [200, {}, { "tasks" => tasks }.to_json]
  end

  # Mock endpoint for fetching all tasks for a user
  get "/agents/tasks" do
    tasks = self.class.all_tasks

    if params[:task_ids].present?
      ids = params[:task_ids].split(",")
      ids_set = ids.to_set
      tasks = tasks.select { |t| ids_set.include?(t["id"]) }
    end

    result = filter_and_paginate_tasks(
      tasks: tasks,
      creator_id_filter: params[:creator_id],
      archived_filter: params[:archived],
      custom_agent_name_filter: params[:custom_agent_name],
      page_size: params[:page_size],
      page_number: params[:page_number],
      page: params[:page],
      per_page: params[:per_page],
      include_counts: params[:include_counts],
    )

    [200, {}, result.to_json]
  end

  # Mock endpoint for fetching tasks for a repository
  get "/agents/repos/:owner/:repo/tasks" do
    owner_login = params[:owner]
    repo_name = params[:repo]

    nwo = "#{owner_login}/#{repo_name}"
    repo = Repository.nwo(nwo)
    return [404, { "Content-Type" => "application/json" }, { error: "Repository not found" }.to_json] unless repo

    # Get all tasks and filter by repo
    all_tasks = self.class.all_tasks
    repo_tasks = all_tasks.select { |t| t.dig("repository", "id") == repo.id }

    result = filter_and_paginate_tasks(
      tasks: repo_tasks,
      creator_id_filter: params[:creator_id],
      archived_filter: params[:archived],
      custom_agent_name_filter: params[:custom_agent_name],
      page_size: params[:page_size],
      page_number: params[:page_number],
      page: params[:page],
      per_page: params[:per_page],
      include_counts: params[:include_counts],
      repo: repo
    )

    [200, {}, result.to_json]
  end

  # Mock endpoint for creating a new task
  post "/agents/repos/:owner/:repo/tasks" do
    body_params = body_json_from(request)
    owner_login = params[:owner]
    repo_name = params[:repo]
    nwo = "#{owner_login}/#{repo_name}"

    # Get request parameters (matching createTaskRequest struct)
    problem_statement = body_params["problem_statement"]
    event_content = body_params["event_content"] || problem_statement
    event_identifiers = body_params["event_identifiers"]
    model = body_params["model"]
    agent_id = body_params["agent_id"] || self.class.copilot_agent_id
    custom_agent = body_params["custom_agent"]
    create_pull_request = body_params["create_pull_request"] != false
    base_ref = body_params["base_ref"]
    event_type = body_params["event_type"] || "api_call_received"

    # Validate - event_content or problem_statement required
    if (event_content.nil? || event_content.strip.empty?) && (problem_statement.nil? || problem_statement.strip.empty?)
      return [400, { "Content-Type" => "application/json" }, { error: "problem_statement or event_content is required" }.to_json]
    end

    # Find the repository
    repo = Repository.nwo(nwo)
    unless repo
      return [404, { "Content-Type" => "application/json" }, { error: "Repository not found" }.to_json]
    end

    # Get current user (mock)
    current_user = User.find_by(login: "monalisa")
    unless current_user
      return [401, { "Content-Type" => "application/json" }, { error: "User not found" }.to_json]
    end

    # Create a new branch with a commit
    branch_name = "copilot-task-#{SecureRandom.hex(8)}"
    base_ref_name = base_ref || repo.default_branch
    base_ref_obj = repo.heads.find_or_build(base_ref_name)
    head_ref = repo.heads.create(branch_name, base_ref_obj.target, current_user)
    head_ref.append_commit({ message: "copilot changes", committer: current_user }, current_user) do |files|
      files.add("README.md", "# Copilot Task\n\n#{event_content}")
    end

    # Create a new branch and pull request if requested
    pull = nil
    if create_pull_request
      title = "[WIP] #{(event_content || problem_statement).to_s.truncate(100)}"
      pull = PullRequest.create_for!(
        repo,
        user: current_user,
        base: base_ref_name,
        head: branch_name,
        title: title,
        body: generate_dynamic_pull_body
      )
    end

    # Generate task ID and agent task ID (assignment ID)
    task_id = SecureRandom.uuid
    agent_task_id = "assignment-#{SecureRandom.hex(8)}"
    now = Time.current

    # Also create an initial session for the task so it can be viewed
    session_id = SecureRandom.uuid
    initial_session = {
      "id" => session_id,
      "name" => event_content || problem_statement,
      "user" => { "id" => current_user.id },
      "agent_id" => agent_id,
      "model" => model,
      "state" => "in_progress",
      "logs" => "",
      "owner" => { "id" => repo.owner.id },
      "repository" => { "id" => repo.id },
      "resource_type" => "",
      "resource_id" => 0,
      "resource_global_id" => "",
      "last_updated_at" => now,
      "created_at" => now,
      "completed_at" => nil,
      "premium_requests" => 0,
      "workflow_run_id" => nil,
      "log_entries" => [],
      "error" => nil,
      "event_type" => event_type,
      "task_id" => task_id,
      "custom_agent" => custom_agent,
      "event_content" => event_content || problem_statement,
      "event_identifiers" => event_identifiers,
    }
    self.class.add_session(initial_session)

    task = {
      "id" => task_id,
      "creator" => { "id" => current_user.id },
      "user_collaborators" => [current_user.id],
      "agent_collaborators" => [
        {
          "agent_type" => "Integration",
          "agent_id" => agent_id,
          "agent_task_id" => agent_task_id
        }
      ],
      "owner" => { "id" => repo.owner.id },
      "repository" => { "id" => repo.id },
      "status" => "in_progress",
      "session_count" => 1,
      "sessions" => [initial_session],
      "artifacts" => [{
          "provider" => "github",
          "type" => "branch",
          "data" => {
            "base_ref" => base_ref_name,
            "head_ref" => head_ref.name,
          },
        },
        if create_pull_request
          {
            "provider" => "github",
            "type" => "github_resource",
            "data" => {
              "id" => pull.id,
              "type" => "pull",
              "global_id" => pull.global_relay_id
            }
          }
        end
      ].compact,
      "archived_at" => nil,
      "last_updated_at" => now.iso8601,
      "created_at" => now.iso8601
    }

    # Store task in cache
    self.class.add_task(task)

    [201, { "Content-Type" => "application/json" }, { "task" => task }.to_json]
  end

  # Mock endpoint for archiving a task
  post "/agents/repos/:owner/:repo/tasks/:task_id/archive" do
    task_id = params[:task_id]

    existing_task = self.class.find_task(task_id)
    unless existing_task
      return [404, { "Content-Type" => "application/json" }, { error: "Task not found" }.to_json]
    end

    now = Time.current
    updates = {
      "archived_at" => now.iso8601,
      "last_updated_at" => now.iso8601
    }
    self.class.update_task(task_id, updates)

    [200, {}, ""]
  end

  # Mock endpoint for creating a session for an existing task
  post "/agents/repos/:owner/:repo/tasks/:task_id/sessions" do
    body_params = body_json_from(request)
    owner_login = params[:owner]
    repo_name = params[:repo]
    task_id = params[:task_id]
    nwo = "#{owner_login}/#{repo_name}"

    # Get request parameters (matching createSessionForTaskRequest struct)
    problem_statement = body_params["problem_statement"]
    event_content = body_params["event_content"] || problem_statement
    model = body_params["model"]
    agent_id = body_params["agent_id"]
    custom_agent = body_params["custom_agent"]
    create_pull_request = body_params["create_pull_request"] != false
    base_ref = body_params["base_ref"]
    event_type = body_params["event_type"] || "api_call_received"

    # Validate - event_content or problem_statement required
    if (event_content.nil? || event_content.strip.empty?) && (problem_statement.nil? || problem_statement.strip.empty?)
      return [400, { "Content-Type" => "application/json" }, { error: "problem_statement or event_content is required" }.to_json]
    end

    if task_id.nil? || task_id.strip.empty?
      return [400, { "Content-Type" => "application/json" }, { error: "task_id is required" }.to_json]
    end

    repo = Repository.nwo(nwo)
    unless repo
      return [404, { "Content-Type" => "application/json" }, { error: "Repository not found" }.to_json]
    end

    current_user = User.find_by(login: "monalisa")
    unless current_user
      return [401, { "Content-Type" => "application/json" }, { error: "User not found" }.to_json]
    end

    # Find existing task from cache
    existing_task = self.class.find_task(task_id)
    unless existing_task
      return [404, { "Content-Type" => "application/json" }, { error: "Task not found" }.to_json]
    end

    # Determine agent ID (default to most recent collaborator if not specified)
    if agent_id.nil? || agent_id == 0
      last_collaborator = existing_task["agent_collaborators"]&.last
      agent_id = last_collaborator&.dig("agent_id") || self.class.copilot_agent_id
    end

    # Get artifact info from task for the session
    artifact = existing_task["artifacts"]&.first
    resource_id = artifact&.dig("data", "id")
    resource_global_id = artifact&.dig("data", "global_id")
    resource_type = artifact&.dig("data", "type")

    now = Time.current

    # Create a new session for the existing task
    new_session = {
      "id" => SecureRandom.uuid,
      "name" => event_content || problem_statement,
      "user" => { "id" => current_user.id },
      "agent_id" => agent_id,
      "model" => model,
      "state" => "queued",
      "logs" => "",
      "owner" => { "id" => repo.owner.id },
      "repository" => { "id" => repo.id },
      "resource_type" => resource_type,
      "resource_id" => resource_id,
      "resource_global_id" => resource_global_id,
      "last_updated_at" => now,
      "created_at" => now,
      "completed_at" => nil,
      "premium_requests" => 0,
      "workflow_run_id" => nil,
      "log_entries" => [],
      "error" => nil,
      "event_type" => event_type,
      "task_id" => task_id,
      "custom_agent" => custom_agent,
      "event_content" => event_content || problem_statement,
    }

    # Store new session in cache
    self.class.add_session(new_session)

    # Update the task with new session count and collaborators
    task_updates = {
      "session_count" => (existing_task["session_count"] || 0) + 1,
      "last_updated_at" => now.iso8601,
      "status" => "queued"
    }
    # Add user to collaborators if not already present
    user_collaborators = existing_task["user_collaborators"] || []
    unless user_collaborators.include?(current_user.id)
      task_updates["user_collaborators"] = user_collaborators + [current_user.id]
    end
    self.class.update_task(task_id, task_updates)

    # Return 202 Accepted (job creation is asynchronous, per copilot-api)
    [202, {}, ""]
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

  # Mock endpoint for fetching a specific task by ID
  get "/agents/repos/:owner/:repo/tasks/:task_id" do
    task_id = params[:task_id]
    owner_login = params[:owner]
    repo_name = params[:repo]
    nwo = "#{owner_login}/#{repo_name}"

    repository = Repository.nwo(nwo)
    return [404, { "Content-Type" => "application/json" }, { error: "Repository not found" }.to_json] unless repository

    # Find task from cache
    task = self.class.find_task(task_id)
    return [404, { "Content-Type" => "application/json" }, { error: "Task not found" }.to_json] unless task

    # Verify task belongs to this repository
    if task.dig("repository", "id") != repository.id
      return [404, { "Content-Type" => "application/json" }, { error: "Task not found" }.to_json]
    end

    # Ensure artifacts have valid PRs
    task = attach_valid_objects_to_task(task, repository)

    # Get sessions for this task
    task_sessions = sessions.select { |s| s["task_id"] == task_id }

    # Return response matching GetTaskResponse struct
    response = task.merge("sessions" => task_sessions)
    [200, { "Content-Type" => "application/json" }, response.to_json]
  end

  # Mock endpoint for fetching inactive logs for a task
  get "/agents/repos/:owner/:repo/tasks/:task_id/inactive_logs" do
    task_id = params[:task_id]
    owner_login = params[:owner]
    repo_name = params[:repo]
    nwo = "#{owner_login}/#{repo_name}"

    repository = Repository.nwo(nwo)
    return [404, { "Content-Type" => "application/json" }, { error: "Repository not found" }.to_json] unless repository

    # Find task from cache
    task = self.class.find_task(task_id)
    return [404, { "Content-Type" => "application/json" }, { error: "Task not found" }.to_json] unless task

    # Verify task belongs to this repository
    if task.dig("repository", "id") != repository.id
      return [404, { "Content-Type" => "application/json" }, { error: "Task not found" }.to_json]
    end

    # Get inactive sessions for this task
    task_sessions = sessions.select { |s| s["task_id"] == task_id }
    inactive_sessions = task_sessions.select { |session| %w[completed cancelled failed].include?(session["state"]) }

    # Build logs hash for inactive sessions
    inactive_logs_hash = inactive_sessions.each_with_object({}) do |session, hash|
      hash[session["id"]] = format_session_logs(session["id"])
    end

    [200, { "Content-Type" => "application/json" }, { logs: inactive_logs_hash }.to_json]
  end

  private

  # Shared helper for filtering and paginating tasks
  # Used by both /agents/tasks and /agents/repos/:owner/:repo/tasks endpoints
  def filter_and_paginate_tasks(tasks:, creator_id_filter: nil, archived_filter: nil, custom_agent_name_filter: nil, page_size: nil, page_number: nil, page: nil, per_page: nil, include_counts: nil, repo: nil)
    # Support both legacy (page_size/page_number) and REST-style (per_page/page) params
    page_size = (per_page || page_size || 10).to_i
    page_number = (page || page_number || 1).to_i

    filtered_tasks = tasks

    # Filter by archived status if provided
    unless archived_filter.nil?
      is_archived = archived_filter == "true"
      filtered_tasks = filtered_tasks.select do |t|
        is_archived ? t["archived_at"].present? : t["archived_at"].nil?
      end
    end

    # Filter by creator_id if provided (supports both single value and arrays)
    if creator_id_filter.present?
      creator_ids = Array(creator_id_filter).map(&:to_s)
      filtered_tasks = filtered_tasks.select { |t| creator_ids.include?(t.dig("creator", "id").to_s) }
    end

    # Filter by custom_agent_name if provided (supports both single value and arrays)
    if custom_agent_name_filter.present?
      agent_names = Array(custom_agent_name_filter).map(&:to_s)
      filtered_tasks = filtered_tasks.select { |t| agent_names.include?(t["custom_agent_name"].to_s) }
    end

    # Sort by updated_at (or legacy last_updated_at) descending
    filtered_tasks = filtered_tasks.sort_by { |t| t["updated_at"] || t["last_updated_at"] || "" }.reverse

    # Pagination
    total_tasks = filtered_tasks.size
    start_index = (page_number - 1) * page_size
    paginated_tasks = filtered_tasks[start_index, page_size] || []
    has_next_page = (start_index + page_size) < total_tasks
    total_archived_count = tasks.count { |t| t["archived_at"].present? }
    total_active_count = tasks.size - total_archived_count

    # Ensure artifacts have valid PRs (attach real objects if needed) when repo is provided
    if repo
      paginated_tasks = paginated_tasks.map { |t| attach_valid_objects_to_task(t, repo) }
    end

    response = {
      "tasks" => paginated_tasks,
      "has_next_page" => has_next_page,
    }

    # Only include counts if requested
    if include_counts == "true"
      response["total_archived_count"] = total_archived_count
      response["total_active_count"] = total_active_count
    end

    response
  end

  # Ensure task artifacts (PRs) have valid objects attached for rendering
  # Similar to attach_valid_objects but for tasks
  def attach_valid_objects_to_task(task, repo)
    return task unless task && repo

    task_copy = task.dup
    task_copy["artifacts"] ||= []

    # Process each artifact to ensure valid PR objects exist
    task_copy["artifacts"] = task_copy["artifacts"].map do |artifact|
      next artifact unless artifact["provider"] == "github"

      artifact_data = artifact["data"]
      next artifact unless artifact_data

      # Try to find the PR by ID
      pr_id = artifact_data["id"]
      if pr_id
        pr = repo.pull_requests.find_by(id: pr_id)
        if pr
          # Update with actual PR data
          artifact.merge(
            "data" => {
              "id" => pr.id,
              "type" => "pull",
              "global_id" => pr.global_relay_id
            }
          )
        else
          # PR not found, try to use first available PR or create one
          fallback_pr = repo.pull_requests.first
          if fallback_pr
            artifact.merge(
              "data" => {
                "id" => fallback_pr.id,
                "type" => "pull",
                "global_id" => fallback_pr.global_relay_id
              }
            )
          else
            artifact
          end
        end
      else
        artifact
      end
    end

    task_copy
  end

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

  # Returns [category, priority, summary, recommendation, ctas] based on notification subject type
  # for the /agents/github-notifications-digest fauxpilot endpoint.
  def mock_notification_digest_item(subject_type, index)
    case subject_type
    when "PullRequest"
      categories = ["Needs your review", "Ready for next steps", "Waiting on others"]
      [
        categories[index % categories.length],
        8,
        "You were specifically requested to review this pull request. Review the latest changes and provide feedback.",
        "Review pull request to update Readme.md",
        ["Review pull request", "Add a comment"],
      ]
    when "Issue"
      [
        "Active conversations",
        6,
        "This issue has recent activity. Consider adding a comment or closing if resolved.",
        "Reply to new comments",
        ["Add a comment", "Close Issue"],
      ]
    when "CheckSuite", "WorkflowRun"
      [
        "CI/CD failures",
        9,
        "A workflow run requires your attention. Check the logs for failures.",
        "Resolve failing workflow run",
        ["View checks"],
      ]
    when "RepositoryVulnerabilityAlert", "SecurityAdvisory", "RepositoryAdvisory"
      [
        "Security concerns",
        10,
        "A security advisory has been published. Review and remediate as soon as possible.",
        "Review new security advisory",
        [],
      ]
    when "Discussion"
      [
        "Active conversations",
        5,
        "A discussion you're subscribed to has new replies. Consider joining the conversation.",
        "Reply to new discussion comments",
        ["Reply to discussion", "View latest comments"],
      ]
    when "Release"
      [
        "Ready for next steps",
        4,
        "A new release has been published. Review the changelog for relevant changes.",
        "Review new release",
        ["View latest comments"],
      ]
    else
      [
        "Other",
        3,
        "This notification may need your attention. Review it when you have a moment.",
        "Review this notification",
        [],
      ]
    end
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
        user: user,
        base: repo.default_branch,
        head: branch_name,
        title: Faker::Lorem.sentence,
        body: generate_dynamic_pull_body
      )
      GitHub.cache.set("copilot_swe_agent_map_resource_id#{session['resource_id']}", pull_to_use.id)
    else
      # Update the body of existing pull request every time it's accessed
      update_pull_request_body(pull_to_use)
      # Reload the pull request to ensure we have the updated data
      pull_to_use.reload
    end
    session.merge!("resource_global_id" => pull_to_use.global_relay_id, "resource_id" => pull_to_use.id)

    # If not the initial implementation and not already a non-PR-comment session,
    # subsequent sessions should have valid comments attached to them
    non_pr_comment_event_types = %w[api_call_received copilot_chat_spec_task issues_agent_assignment]
    if session["name"] != "Initial implementation" && !non_pr_comment_event_types.include?(session["event_type"])
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
    all_sessions = self.class.all_sessions
    all_sessions.map do |session|
      # Work on a copy to avoid mutating cached data
      session = session.dup

      # Replace agent IDs used in session response with the local agent ids to make sure they match for grabbing agent info
      if session["agent_id"] == 1143301
        session["agent_id"] = self.class.copilot_agent_id
      elsif session["agent_id"] == 838
        session["agent_id"] = self.class.test_agent_id
      end

      # Ensure repository id is valid - if not, use monalisa/smile's repo id
      repo_id = session.dig("repository", "id")
      if repo_id && !Repository.find_by(id: repo_id)
        smile_repo = Repository.nwo("monalisa/smile")
        session["repository"] = { "id" => smile_repo.id } if smile_repo
      end

      attach_valid_objects(session)
    end
  end

  def user_sessions
    current_user = User.find_by(login: "monalisa")

    sessions.select do |session|
      session.dig("user", "id").to_i == current_user&.id
    end
  end

  def user_sessions_for_pr(pull_id)
    # For local development, return sessions even if PR ID doesn't match exactly
    # This makes testing easier since mock data has hardcoded resource_ids
    matching_sessions = user_sessions.select do |session|
      simplified_session = session.transform_keys(&:to_sym)
      simplified_session[:resource_id].to_i == pull_id
    end

    # If no exact match, return the first session with model set (for testing current_model feature)
    if matching_sessions.empty? && Rails.env.development?
      return user_sessions.select { |s| s["model"].present? }.first(1)
    end

    matching_sessions
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
