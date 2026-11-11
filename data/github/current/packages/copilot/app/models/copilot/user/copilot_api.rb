# typed: strict
# frozen_string_literal: true

# rubocop:disable Sorbet/ForbidTUntyped

class Copilot::User::CopilotApi
  class ContentFilterMode < T::Enum
    enums do
      None = new("none")
      Markdown = new("markdown")
      HiddenCharacters = new("hidden_characters")
    end
  end

  sig { returns User }
  attr_reader :user

  sig { returns T.nilable(UserSession) }
  attr_reader :session

  sig { returns T.nilable(String) }
  attr_reader :request_id

  sig { returns T.nilable(String) }
  attr_reader :real_ip

  sig { returns T.nilable(T.any(Copilot::DecryptedToken, Copilot::EncryptedToken)) }
  attr_reader :token

  SSAT_SCOPE_GITHUB_CHAT = "CopilotAPI:GitHubChat"
  SSAT_SCOPE_GITHUB_DOCSETS = "CopilotAPI:GitHubDocsets"
  SSAT_SCOPE_OPENAI = "CopilotAPI:OpenAI"

  # DEPRECATED. do not use.
  sig do params(
    method: Symbol,
    path: String,
    user: User,
    session: T.nilable(UserSession),
  ).returns(String)
  end
  def self.generate_token(method:, path:, user:, session: nil)
    options = {
      scope: self.token_scope(method, path),
      expires: 30.minutes.from_now,
    }

    if session.nil?
      options[:user] = user
    else
      options[:session] = session
    end

    GitHub::Authentication::SignedAuthToken.generate(**options)
  end

  sig do params(
    method: Symbol,
    path: String,
  ).returns(String)
  end
  def self.token_scope(method, path)
    return SSAT_SCOPE_GITHUB_CHAT if path.start_with?(CopilotAPI::CHAT_BASE_PATH)
    SSAT_SCOPE_OPENAI
  end

  sig do
    params(
      user: T.nilable(User),
      repository: T.nilable(Repository),
      owner: T.nilable(T.any(User, Organization)),
    ).returns(T.nilable(String))
  end
  def self.resolve_swe_agent_staging_env(user: nil, repository: nil, owner: nil)
    CopilotSweAgent::SweAgentPath.resolve_env(user:, repository:, owner:)
  end

  sig do params(
    user: User,
    integration_id: String,
    session: T.nilable(UserSession),
    real_ip: T.nilable(String),
    token: T.nilable(T.any(Copilot::DecryptedToken, Copilot::EncryptedToken)),
    api_version: String,
    request_id: T.nilable(String),
  ).void
  end
  def initialize(user, integration_id:, session:, real_ip:, token: nil, api_version: CopilotAPI::VERSION_DEFAULT, request_id: nil)
    @user = user
    @integration_id = integration_id
    @session = session
    @real_ip = real_ip
    @token = token
    @api_version = api_version
    @request_id = request_id
  end

  sig do params(
    repo_id: T.nilable(Integer),
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def list_threads(repo_id: nil)
    path = "/threads"
    query = repo_id.present? ? { repo_id: repo_id } : {}
    make_request(method: :get, path: CopilotAPI::CHAT_BASE_PATH + path, query: query)
  end

  sig do
    returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def agents
    path = "/agents"
    make_request(method: :get, path:)
  end

  sig do params(
    thread_id: String,
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def get_thread(thread_id:)
    path = "/threads/#{CGI.escape(thread_id)}"
    make_request(method: :get, path: CopilotAPI::CHAT_BASE_PATH + path)
  end

  sig do params(
    repo_id: T.nilable(Integer),
    repo_owner_id: T.nilable(Integer),
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def create_thread(repo_id: nil, repo_owner_id: nil)
    path = "/threads"
    data = { repo_id: repo_id, repo_owner_id: repo_owner_id }
    make_request(method: :post, path: CopilotAPI::CHAT_BASE_PATH + path, data: data)
  end

  sig do params(
    thread_id: String,
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def destroy_thread(thread_id:)
    path = "/threads/#{CGI.escape(thread_id)}"
    make_request(method: :delete, path: CopilotAPI::CHAT_BASE_PATH + path)
  end

  sig { params(thread_id: T.untyped).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess])) }
  def clear_thread(thread_id:)
    path = "/threads/#{CGI.escape(thread_id)}/clear"
    make_request(method: :patch, path: CopilotAPI::CHAT_BASE_PATH + path)
  end

  sig do params(
    thread_id: String,
    name: String,
    generate: T::Boolean,
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def update_thread_name(thread_id:, name: "", generate: true)
    path = "/threads/#{CGI.escape(thread_id)}/name"
    data = { name: name, generate: generate }
    make_request(method: :patch, path: CopilotAPI::CHAT_BASE_PATH + path, data: data)
  end

  sig do params(
    thread_id: String,
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def list_messages(thread_id:)
    path = "/threads/#{CGI.escape(thread_id)}/messages"
    make_request(method: :get, path: CopilotAPI::CHAT_BASE_PATH + path)
  end

  sig do params(
    thread_id: String,
    content: String,
    intent: String,
    references: T::Array[ActiveSupport::HashWithIndifferentAccess]
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def create_message(thread_id:, content:, intent:, references: [])
    path = "/threads/#{CGI.escape(thread_id)}/messages"
    data = { content: content, intent: intent, references: references }
    make_request(method: :post, path: CopilotAPI::CHAT_BASE_PATH + path, data: data)
  end

  sig do params(
    feedback: String,
    feedback_choice: T::Array[String],
    thread_id: String,
    message_id: String,
    text_response: String,
    is_contacted_checked: String,
  ).void
  end
  def send_feedback(feedback:, feedback_choice:, thread_id:, message_id:, text_response: "", is_contacted_checked: "false")
    # Convert "true" or "false" to a boolean value
    is_contacted_checked = is_contacted_checked == "true"

    path = "/threads/#{CGI.escape(thread_id)}/messages/#{CGI.escape(message_id)}/feedback"
    data = { feedback: feedback, text_response: text_response, feedback_choice: feedback_choice, is_contacted_checked: is_contacted_checked }
    make_request(method: :post, path: CopilotAPI::CHAT_BASE_PATH + path, data: data)
  end

  sig do params(
    model: String,
    prompt: String,
    max_tokens: Integer,
    temperature: Float,
    stop: T::Array[String],
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def create_completion(model:, prompt:, max_tokens:, temperature:, stop: [])
    data = { model: model, prompt: [prompt], max_tokens: max_tokens, temperature: temperature }
    unless stop.empty?
      data[:stop] = stop
    end
    make_request(
      path: "/completions",
      method: :post,
      data: data
    )
  end

  sig do params(
    model: String,
    prompt: String,
    max_tokens: Integer,
    temperature: Float,
    stop: T::Array[String],
    initiator: T.nilable(String),
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def async_create_completion(model:, prompt:, max_tokens:, temperature:, stop: [], initiator: nil)
    data = { model: model, prompt: [prompt], max_tokens: max_tokens, temperature: temperature }
    unless stop.empty?
      data[:stop] = stop
    end
    make_request(
      async: true,
      path: "/completions",
      method: :post,
      initiator: initiator,
      data: data
    )
  end

  sig do params(
    model: String,
    messages: T::Array[T.untyped],
    max_tokens: Integer,
    temperature: Float,
    stop: T::Array[String],
    initiator: T.nilable(String),
    response_format: T.nilable(T::Hash[Symbol, T.untyped]),
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def create_chat_completion(model:, messages:, max_tokens:, temperature:, stop: [], initiator: nil, response_format: nil)
    data = { model: model, messages: messages, max_tokens: max_tokens, temperature: temperature }
    unless stop.empty?
      data[:stop] = stop
    end
    data[:response_format] = response_format if response_format
    make_request(
      path: "/chat/completions",
      method: :post,
      initiator: initiator,
      data: data
    )
  end

  sig do params(
    model: String,
    messages: T::Array[T.untyped],
    max_tokens: Integer,
    temperature: Float,
    stop: T::Array[String],
    initiator: T.nilable(String),
    response_format: T.nilable(T::Hash[Symbol, T.untyped]),
    experiment_headers: T::Hash[String, String],
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def async_create_chat_completion(model:, messages:, max_tokens:, temperature:, stop: [], initiator: nil, response_format: nil, experiment_headers: {})
    data = { model: model, messages: messages, max_tokens: max_tokens, temperature: temperature }
    unless stop.empty?
      data[:stop] = stop
    end
    data[:response_format] = response_format if response_format
    make_request(
      async: true,
      path: "/chat/completions",
      method: :post,
      initiator: initiator,
      data: data,
      num_threads: CopilotAPI::MAX_CONCURRENCY,
      experiment_headers: experiment_headers,
    )
  end

  sig do params(
    model: String,
    input: T::Array[T.untyped],
    max_output_tokens: Integer,
    instructions: T.nilable(String),
    reasoning: T.nilable(T::Hash[Symbol, String]),
    initiator: T.nilable(String),
    experiment_headers: T::Hash[String, String],
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def async_create_response(model:, input:, max_output_tokens:, instructions: nil, reasoning: nil, initiator: nil, experiment_headers: {})
    data = { model: model, input: input, max_output_tokens: max_output_tokens }
    data[:instructions] = instructions if instructions
    data[:reasoning] = reasoning if reasoning
    make_request(
      async: true,
      path: "/responses",
      method: :post,
      initiator: initiator,
      data: data,
      num_threads: CopilotAPI::MAX_CONCURRENCY,
      experiment_headers: experiment_headers,
    )
  end

  sig do params(
    model: String,
    input: String,
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def create_embedding(model:, input:)
    data = { model: model, input: [input] }
    make_request(
      path: "/embeddings",
      method: :post,
      data: data
    )
  end

  # Public: Generate a notifications digest using the notifications digest agent.
  #
  # notifications - an array of notification summary hashes (from Copilot::NotificationDigest#notification_summaries)
  # model - the model to use for the digest
  # temperature - the temperature parameter for the model (default: 0.3)
  sig do
    params(
      notifications: T::Array[T::Hash[Symbol, T.untyped]],
      model: String,
      temperature: Float,
      allowed_ctas: T::Array[String],
    ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def create_notifications_digest(notifications:, model:, temperature: 0.3, allowed_ctas: [])
    content = { copilot_notifications: notifications, allowed_ctas: allowed_ctas }.to_json
    messages = [{ role: "user", content: content }]
    make_request(
      path: "/agents/github-notifications-digest",
      method: :post,
      data: { messages: messages, model: model, temperature: temperature }
    )
  end

  # Public: Summarize a piece of GitHub content using Copilot.
  #
  # references - a list of content references as hashes; should correspond to reference types in github/copilot-api,
  #              such as `reference.Discussion` or `reference.Issue`
  # default_prompt - the normal GitHub prompt for how to summarize the content; required
  # custom_prompt - a custom user-provided prompt for how to summarize the content; if both `default_prompt`
  #                 and `custom_prompt` are given, `custom_prompt` will be preferred
  sig do
    params(
      references: T::Array[T::Hash[Symbol, T.untyped]],
      default_prompt: String,
      custom_prompt: T.nilable(String)
    ).returns(T.any(
      ActiveSupport::HashWithIndifferentAccess,
      ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]
    ))
  end
  def summarize(references:, default_prompt:, custom_prompt: nil)
    if custom_prompt.present?
      messages = [
        { role: "system", content: custom_prompt, copilot_references: references },

        # https://github.com/github/copilot-api/pull/6297 made a change that
        # fails requests that do not end with a "user" message
        { role: "user", content: default_prompt, copilot_references: references }
      ]
    else
      messages = [{ role: "user", content: default_prompt, copilot_references: references }]
    end
    make_request(path: "/agents/github-summary", method: :post, data: { messages: messages })
  end

  sig do params(
    owner: String,
    repo: String,
    limit: Integer,
    request_timeout_s: T.nilable(Float),
    staging_env: T.nilable(String),
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def get_top_memories(owner:, repo:, limit: 20, request_timeout_s: nil, staging_env: nil)
    base = CopilotSweAgent::SweAgentPath.base_path(staging_env:)
    make_request(path: "#{base}/internal/memory/v0/#{owner}/#{repo}/top", method: :get, query: { limit: limit }, request_timeout_s: request_timeout_s) # rubocop:disable GitHub/DoNotAllowLogin
  end

  class MemorySearchRequest < T::Struct
    const :Question, String
    const :SHA, String
  end

  sig do params(
    owner: String,
    repo: String,
    query: MemorySearchRequest,
    staging_env: T.nilable(String),
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def search_memories(owner:, repo:, query:, staging_env: nil)
    base = CopilotSweAgent::SweAgentPath.base_path(staging_env:)
    make_request(path: "#{base}/internal/memory/v0/#{owner}/#{repo}/search", method: :post, data: query.to_json) # rubocop:disable GitHub/DoNotAllowLogin
  end

  sig do params(
    owner: String,
    repo: String,
    memory_id: String,
    staging_env: T.nilable(String),
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def delete_memory(owner:, repo:, memory_id:, staging_env: nil)
    base = CopilotSweAgent::SweAgentPath.base_path(staging_env:)
    make_request(path: "#{base}/internal/memory/v0/#{owner}/#{repo}/#{memory_id}", method: :delete) # rubocop:disable GitHub/DoNotAllowLogin
  end

  sig do params(
    owner: String,
    repo: String,
    ids: T::Array[String],
    staging_env: T.nilable(String),
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def delete_memories(owner:, repo:, ids:, staging_env: nil)
    base = CopilotSweAgent::SweAgentPath.base_path(staging_env:)
    make_request(path: "#{base}/internal/memory/v0/#{owner}/#{repo}/delete", method: :post, data: { ids: ids }) # rubocop:disable GitHub/DoNotAllowLogin
  end

  sig do params(
    limit: Integer,
    request_timeout_s: T.nilable(Float),
    staging_env: T.nilable(String),
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def get_top_user_memories(limit: 20, request_timeout_s: nil, staging_env: nil)
    base = CopilotSweAgent::SweAgentPath.base_path(staging_env:)
    make_request(path: "#{base}/internal/memory/v0/user/top", method: :get, query: { limit: limit }, request_timeout_s: request_timeout_s)
  end

  sig do params(
    memory_id: String,
    staging_env: T.nilable(String),
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def delete_user_memory(memory_id:, staging_env: nil)
    base = CopilotSweAgent::SweAgentPath.base_path(staging_env:)
    make_request(path: "#{base}/internal/memory/v0/user/#{memory_id}", method: :delete)
  end

  sig do params(
    ids: T::Array[String],
    staging_env: T.nilable(String),
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def delete_user_memories(ids:, staging_env: nil)
    base = CopilotSweAgent::SweAgentPath.base_path(staging_env:)
    make_request(path: "#{base}/internal/memory/v0/user/delete", method: :post, data: { ids: ids })
  end

  sig { returns(ConditionalAccess::Model::Filter) }
  def cap_filter
    @conditional_access_filter = T.let(nil, T.nilable(ConditionalAccess::Model::Filter))
    @conditional_access_filter || ConditionalAccess::Model::Filter.new(self, location: :model, actor: user, remote_ip: real_ip, web_session: session) # rubocop:todo GitHub/DoNotInstantiatePlatformObjects
  end

  sig do params(
    role: String,
    references: T::Array[T::Hash[T.untyped, T.untyped]],
    experiment_headers: T::Hash[String, String],
    interaction_id: String,
    interaction_type: String,
    initiator: String,
    snippy_token: T.nilable(String),
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def create_code_review(
    role:,
    references:,
    experiment_headers:,
    interaction_id:,
    interaction_type:,
    initiator:,
    snippy_token: nil
  )
    data = {
      messages: [{
        role: role,
        copilot_references: references
      }],
    }

    # Get headers from request that start with X-Experiment-
    make_request(
      path: "/agents/github-code-review",
      method: :post,
      data:,
      experiment_headers:,
      interaction_id:,
      interaction_type:,
      initiator:,
      snippy_token:,
      retry_401s: true,
    )
  end

  sig do params(
    repo_id: Integer,
    pull_request_id: Integer,
    head_sha: String,
    view: T.nilable(String),
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def get_findings(repo_id:, pull_request_id:, head_sha:, view: nil)
    query = { pull_request_id: pull_request_id, head_sha: head_sha, repo_id: repo_id }
    query[:view] = view if view.present?

    make_request(
      method: :get,
      path: "/agents/ccr/findings",
      query: query,
      extract_retry_after_header: true,
      retry_401s: true,
    )
  end

  sig do params(
    head_sha: T.nilable(String),
    repo_id: T.nilable(Integer),
    check_suite_id: T.nilable(Integer),
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def get_ci_findings(head_sha: nil, repo_id: nil, check_suite_id: nil)
    query = if head_sha
      raise ArgumentError, "repo_id is required with head_sha" unless repo_id
      { head_sha: head_sha, repo_id: repo_id }
    elsif check_suite_id
      { check_suite_id: check_suite_id }
    else
      raise ArgumentError, "head_sha or check_suite_id is required"
    end

    make_request(
      method: :get,
      path: "/agents/ccr/ci-findings",
      query: query,
    )
  end

  sig do params(
    repo_id: Integer,
    pull_request_id: Integer,
    head_sha: String,
    updates: T::Array[T::Hash[Symbol, T.untyped]],
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def batch_update_findings(repo_id:, pull_request_id:, head_sha:, updates:)
    data = {
      pullRequestId: pull_request_id,
      headSha: head_sha,
      updates: updates,
    }

    make_request(
      method: :patch,
      path: "/agents/ccr/findings",
      data: data,
      query: { repo_id: repo_id },
    )
  end

  sig do params(
    role: String,
    references: T::Array[T::Hash[T.untyped, T.untyped]],
    experiment_headers: T::Hash[String, String],
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def classify_code_comment(role:, references:, experiment_headers:)
    data = {
      messages: [{
        role: role,
        copilot_references: references
      }],
    }
    # Get headers from request that start with X-Experiment-
    make_request(
      path: "/agents/github-comment-classifier",
      method: :post,
      data: data,
      experiment_headers: experiment_headers,
    )
  end

  sig do params(
    role: String,
    references: T::Array[T::Hash[T.untyped, T.untyped]],
    experiment_headers: T::Hash[String, String],
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def suggested_changes(role:, references:, experiment_headers:)
    data = {
      messages: [{
        role: role,
        copilot_references: references
      }],
    }

    # Get headers from request that start with X-Experiment-
    make_request(
      path: "/agents/github-code-reviser",
      method: :post,
      data: data,
      experiment_headers: experiment_headers,
    )
  end

  sig do params(
    session_id: String,
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def get_swe_agent_logs(session_id:)
    path = "agents/sessions/#{CGI.escape(session_id)}/logs"
    make_request(method: :get, path:, retry_401s: true)
  end

  sig do params(
    session_id: String,
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def get_swe_agent_session(session_id:)
    path = "agents/sessions/#{CGI.escape(session_id)}"
    make_request(method: :get, path:, retry_401s: true)
  end

  sig do params(
    repo_owner: String,
    repo_name: String,
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def get_swe_agent_automations(repo_owner:, repo_name:)
    path = "agents/repos/#{repo_owner}/#{repo_name}/automations"
    make_request(method: :get, path:, retry_401s: true)
  end

  sig do params(
    repo_owner: String,
    repo_name: String,
    automation_id: String,
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def get_swe_agent_automation(repo_owner:, repo_name:, automation_id:)
    path = "agents/repos/#{repo_owner}/#{repo_name}/automations/#{automation_id}"
    make_request(method: :get, path:, retry_401s: true)
  end

  sig { returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess])) }
  def get_automations_tools
    make_request(method: :get, path: "agents/automations/tools", retry_401s: true)
  end

  sig { returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess])) }
  def get_automations_triggers
    make_request(method: :get, path: "agents/automations/triggers", retry_401s: true)
  end

  sig do params(
    automation_id: String,
    page_number: T.nilable(Integer),
    page_size: T.nilable(Integer),
    sort_field: T.nilable(String),
    sort_direction: T.nilable(String),
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def list_automation_tasks(automation_id:, page_number: nil, page_size: nil, sort_field: nil, sort_direction: nil)
    path = "agents/automations/#{automation_id}/tasks"
    query = to_query_params(page_number:, page_size:, sort_field:, sort_direction:)
    make_request(method: :get, path:, query:, extract_link_header: true)
  end

  sig do params(
    resource_type: String,
    resource_id: Integer,
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def get_swe_agent_sessions(resource_type:, resource_id:)
    path = "agents/sessions/resource/#{resource_type}/#{resource_id}"
    make_request(method: :get, path:, retry_401s: true)
  end

  sig do
    params(
      page_number: T.nilable(Integer),
      page_size: T.nilable(Integer),
      sort_field: T.nilable(String),
      sort_direction: T.nilable(String),
      session_states: T.nilable(T::Array[String]),
      event_identifiers: T.nilable(T::Array[String]),
    ).returns(
      T.any(
        ActiveSupport::HashWithIndifferentAccess,
        ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]
      )
    )
  end
  def list_user_swe_agent_sessions(
    page_number: nil,
    page_size: nil,
    sort_field: nil,
    sort_direction: nil,
    session_states: nil,
    event_identifiers: nil
  )
    path = "agents/sessions"
    query = to_query_params(page_number:, page_size:, sort_field:, sort_direction:, session_states:)
    query[:event_identifiers] = event_identifiers.join(",") if event_identifiers.present?

    make_request(method: :get, path:, query:)
  end

  sig do
    params(
      owner_display_login: String,
      repo: String,
      owner_filter: T.nilable(Integer),
      creator_ids: T.nilable(T::Array[Integer]),
      archived_filter: T.nilable(T::Boolean),
      session_states: T.nilable(T::Array[String]),
      task_ids: T::Array[String],
      page_number: T.nilable(Integer),
      page_size: T.nilable(Integer),
      sort_field: T.nilable(String),
      sort_direction: T.nilable(String),
      artifact_type: T.nilable(String),
      type: T.nilable(String),
      include_agent_ids: T.nilable(T::Array[Integer]),
      custom_agent_name: T.nilable(String),
      custom_agent_names: T.nilable(T::Array[String]),
      artifact_state: T.nilable(String),
      q: T.nilable(String),
    ).returns(
      T.any(
        ActiveSupport::HashWithIndifferentAccess,
        ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]
      )
    )
  end
  def list_repo_tasks(
    owner_display_login:,
    repo:,
    owner_filter: nil,
    creator_ids: nil,
    archived_filter: nil,
    session_states: nil,
    task_ids: [],
    page_number: nil,
    page_size: nil,
    sort_field: nil,
    sort_direction: nil,
    artifact_type: nil,
    type: nil,
    include_agent_ids: nil,
    custom_agent_name: nil,
    custom_agent_names: nil,
    artifact_state: nil,
    q: nil
  )
    path = "agents/repos/#{owner_display_login}/#{repo}/tasks"
    query = {}.tap do |query|
      # Prefer creator_ids (multi-value) over legacy owner_filter (single value)
      if creator_ids&.any?
        query[:creator_id] = creator_ids
      elsif owner_filter
        query[:creator_id] = owner_filter
      end
      query[:archived] = archived_filter unless archived_filter.nil?
      if task_ids.any?
        query["task_ids[]"] = task_ids.join(",")
      end
      query[:artifact_type] = artifact_type unless artifact_type.nil?
      query[:artifact_state] = artifact_state unless artifact_state.nil?
      query[:type] = type unless type.nil?
      query[:include_agent_ids] = include_agent_ids.join(",") if include_agent_ids&.any?
      query[:custom_agent_name] = custom_agent_name unless custom_agent_name.nil?
      if custom_agent_names&.any?
        query[:custom_agent_name] = custom_agent_names
      end
      query[:q] = q unless q.nil?
    end
    query.merge!(to_query_params(page_number:, page_size:, sort_field:, sort_direction:, session_states:))

    make_request(method: :get, path:, query:, extract_link_header: true)
  end

  sig do
    params(
      page_number: T.nilable(Integer),
      page_size: T.nilable(Integer),
      sort_field: T.nilable(String),
      sort_direction: T.nilable(String),
      session_states: T.nilable(T::Array[String]),
      archived: T.nilable(T::Boolean),
      artifact_type: T.nilable(String),
      task_ids: T.nilable(T::Array[String]),
      include_agent_ids: T.nilable(T::Array[Integer]),
    )
    .returns(
      T.any(
        ActiveSupport::HashWithIndifferentAccess,
        ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]
      )
    )
  end
  def list_user_tasks(
    page_number: nil,
    page_size: nil,
    sort_field: nil,
    sort_direction: nil,
    session_states: nil,
    archived: nil,
    artifact_type: nil,
    task_ids: nil,
    include_agent_ids: nil
  )
    path = "agents/tasks"
    query = to_query_params(
      page_number:,
      page_size:,
      sort_field:,
      sort_direction:,
      session_states:,
      state_key: use_rest_style_api? ? :state : :status,
    )

    query[:archived] = archived unless archived.nil?
    query[:artifact_type] = artifact_type unless artifact_type.nil?
    query[:task_ids] = task_ids.join(",") if task_ids.present?
    query[:include_agent_ids] = include_agent_ids.join(",") if include_agent_ids&.any?

    make_request(method: :get, path:, query:, extract_link_header: true)
  end

  sig do
    params(
      task_ids: T::Array[String],
      request_timeout_s: T.nilable(Float),
    ).returns(
      T.any(
        ActiveSupport::HashWithIndifferentAccess,
        ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]
      )
    )
  end
  def batch_tasks(task_ids:, request_timeout_s: nil)
    path = "agents/tasks/batch"
    query = { task_ids: task_ids.join(",") }

    make_request(method: :get, path:, query:, request_timeout_s:)
  end

  sig do
    params(
      id: String,
    ).returns(
      T.any(
        ActiveSupport::HashWithIndifferentAccess,
        ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]
      )
    )
  end
  def get_user_task(id:)
    path = "agents/tasks/#{id}"
    make_request(method: :get, path:)
  end

  sig do
    params(
      owner_display_login: String,
      repo: String,
      task_id: String,
    ).returns(
      T.any(
        ActiveSupport::HashWithIndifferentAccess,
        ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]
      )
    )
  end
  def get_task(owner_display_login:, repo:, task_id:)
    path = "agents/repos/#{owner_display_login}/#{repo}/tasks/#{task_id}"
    make_request(method: :get, path:)
  end

  sig do params(
    nwo: String,
    problem_statement: String,
    creation_id: String,
    event_type: String,
    agent_id: T.nilable(Integer), # this is temporarily nilable to allow backward compatibility / @arthurnn
    event_identifiers: T::Array[String],
    event_url: T.nilable(String),
    event_content: T.nilable(String),
    base_ref: T.nilable(String),
    pull_request_data: T.nilable(T::Hash[Symbol, T.untyped]),
    api_version: T.nilable(String),
    staging_env: T.nilable(String),
    use_staging: T::Boolean,
    use_staging_jedi_knight: T::Boolean,
    use_staging_sith_lord: T::Boolean,
    use_staging_baby_yoda: T::Boolean,
    async: T::Boolean,
    request_timeout_s: T.nilable(Float),
    num_threads: Integer,
    content_filter_mode: T.nilable(ContentFilterMode),
    # todo: remove this once we have migrated all clients to use `custom_agent`
    subagent: T.nilable(String),
    custom_agent: T.nilable(String),
    model: T.nilable(String),
    skip_pull_request: T.nilable(T::Boolean),
    skip_notification: T::Boolean,
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def create_swe_agent_job(nwo:, problem_statement:, creation_id:, event_type:, agent_id: nil, event_identifiers: [], event_url: nil, event_content: nil, base_ref: nil, pull_request_data: nil, api_version: nil, staging_env: nil, use_staging: false, use_staging_jedi_knight: false, use_staging_sith_lord: false, use_staging_baby_yoda: false, async: false, request_timeout_s: nil, num_threads: 1, content_filter_mode: nil, subagent: nil, custom_agent: nil, model: nil, skip_pull_request: false, skip_notification: false)
    default_pull_request_data = { title: problem_statement }
    default_pull_request_data[:base_ref] = base_ref if base_ref

    pull_request = default_pull_request_data.merge(pull_request_data || {})

    pull_request = nil if skip_pull_request

    agent = custom_agent || subagent

    data = {
      problem_statement: problem_statement,
      content_filter_mode: content_filter_mode,
      pull_request: pull_request,
      event_identifiers: [creation_id, *event_identifiers],
      event_type: event_type,
      event_url: event_url,
      event_content: event_content,
      custom_agent: agent,
      subagent: agent,
      model: model
    }

    data[:features] = { branch: { base_ref: base_ref }.compact } if skip_pull_request
    data[:skip_notification] = true if skip_notification

    data[:agent_id] = agent_id if agent_id
    make_request(method: :post, path: CopilotSweAgent::SweAgentPath.job_path(nwo: nwo, api_version: api_version, staging_env: staging_env, use_staging: use_staging, use_staging_jedi_knight: use_staging_jedi_knight, use_staging_sith_lord: use_staging_sith_lord, use_staging_baby_yoda: use_staging_baby_yoda), data: data, async: async, request_timeout_s: request_timeout_s, num_threads: num_threads)
  end

  # Calls the Copilot API to create a new task for the given repository.
  # Null argument values indicate that the corresponding parameter should be omitted from the request payload.
  sig do
    params(
      nwo: String,
      agent_id: T.nilable(Integer),
      base_ref: T.nilable(String),
      create_pull_request: T.nilable(T::Boolean),
      custom_agent: T.nilable(String),
      event_content: T.nilable(String),
      event_type: T.nilable(String),
      event_url: T.nilable(String),
      head_ref: T.nilable(String),
      model: T.nilable(String),
      problem_statement: T.nilable(String),
      event_identifiers: T::Array[String],
    ).returns(
      T.any(
        ActiveSupport::HashWithIndifferentAccess,
        ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]
      )
    )
  end
  def create_task(
    nwo:,
    agent_id: nil,
    base_ref: nil,
    create_pull_request: nil,
    custom_agent: nil,
    event_content: nil,
    event_type: nil,
    event_url: nil,
    head_ref: nil,
    model: nil,
    problem_statement: nil,
    event_identifiers: []
  )
    path = "agents/repos/#{nwo}/tasks"

    data = {}
    data[:agent_id] = agent_id if agent_id
    data[:base_ref] = base_ref if base_ref
    data[:create_pull_request] = create_pull_request unless create_pull_request.nil?
    data[:custom_agent] = custom_agent if custom_agent
    data[:event_content] = event_content if event_content
    data[:event_type] = event_type if event_type
    data[:event_url] = event_url if event_url
    data[:head_ref] = head_ref if head_ref
    data[:model] = model if model
    data[:problem_statement] = problem_statement if problem_statement
    data[:event_identifiers] = event_identifiers if event_identifiers.any?

    make_request(method: :post, path:, data:)
  end

  private

  sig do params(
    method: Symbol,
    path: String,
    async: T::Boolean,
    data: T.nilable(T::Hash[Symbol, T.untyped]),
    query: T.nilable(T::Hash[Symbol, T.untyped]),
    integration_id: String,
    experiment_headers: T::Hash[String, String],
    interaction_id: T.nilable(String),
    interaction_type: T.nilable(String),
    initiator: T.nilable(String),
    retry_401s: T.nilable(T::Boolean),
    snippy_token: T.nilable(String),
    request_timeout_s: T.nilable(Float),
    num_threads: T.nilable(Integer),
    extract_link_header: T::Boolean,
    extract_retry_after_header: T::Boolean,
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def make_request(
    method:,
    path:,
    async: false,
    data: nil,
    query: {},
    integration_id: @integration_id,
    experiment_headers: {},
    interaction_id: nil,
    interaction_type: nil,
    initiator: nil,
    retry_401s: false,
    snippy_token: nil,
    request_timeout_s: nil,
    num_threads: nil,
    extract_link_header: false,
    extract_retry_after_header: false
  )
    CopilotAPI.make_request(
      async:,
      token:,
      integration_id:,
      method:,
      path:,
      data:,
      query:,
      user_id: user.id,
      real_ip:,
      experiment_headers:,
      interaction_id:,
      interaction_type:,
      initiator:,
      retry_401s:,
      snippy_token:,
      copilot_api_version: @api_version,
      request_id: @request_id,
      request_timeout_s: request_timeout_s,
      num_threads: (num_threads || 1),
      extract_link_header: extract_link_header,
      extract_retry_after_header: extract_retry_after_header
    )
  end

  sig { returns(T::Array[Integer]) }
  def authorized_org_ids
    cap_filter.authorized_resource_ids(user.organizations, only: :saml)
  end

  sig do
    params(
      page_number: T.nilable(Integer),
      page_size: T.nilable(Integer),
      sort_field: T.nilable(String),
      sort_direction: T.nilable(String),
      session_states: T.nilable(T::Array[String]),
      state_key: Symbol
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def to_query_params(
    page_number: nil,
    page_size: nil,
    sort_field: nil,
    sort_direction: nil,
    session_states: nil,
    state_key: :state
  )
    raise ArgumentError, "sort_direction provided without sort_field" if sort_direction && !sort_field
    raise ArgumentError, "sort_field provided without sort_direction" if sort_field && !sort_direction

    rest_style = use_rest_style_api?

    {}.tap do |query|
      if rest_style
        # GitHub REST API-style: separate page/per_page params and sort/direction params
        query[:page] = page_number if page_number
        query[:per_page] = page_size if page_size
        if sort_field && sort_direction
          query[:sort] = to_rest_sort_field(sort_field)
          query[:direction] = sort_direction
        end
      else
        # Legacy style: page_number/page_size and combined sort param
        query[:page_number] = page_number if page_number
        query[:page_size] = page_size if page_size
        query[:sort] = to_sort_param(sort_field:, sort_direction:) if sort_field && sort_direction
      end
      query[state_key] = to_state_param(session_states) if session_states
    end
  end

  sig { params(sort_field: String, sort_direction: String).returns(String) }
  def to_sort_param(sort_field:, sort_direction:)
    "#{sort_field},#{sort_direction}"
  end

  # Maps internal sort field names to GitHub REST API-style field names.
  # e.g. "last_updated_at" -> "updated_at"
  sig { params(sort_field: String).returns(String) }
  def to_rest_sort_field(sort_field)
    field_map = {
      "last_updated_at" => "updated_at",
      "created_at" => "created_at",
    }
    field_map.fetch(sort_field, sort_field)
  end

  sig { returns(T::Boolean) }
  def use_rest_style_api?
    FeatureFlag.vexi.enabled?(:copilot_task_api_github_rest_style, user, default: false)
  end

  sig { params(session_states: T::Array[String]).returns(String) }
  def to_state_param(session_states)
    session_states.join(",")
  end
end
