# typed: strict
# frozen_string_literal: true

# rubocop:disable Sorbet/ForbidTUntyped

class Copilot::User::CopilotApi

  sig { returns User }
  attr_reader :user

  sig { returns T.nilable(UserSession) }
  attr_reader :session

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
    return SSAT_SCOPE_GITHUB_DOCSETS if path.start_with?(CopilotAPI::DOCSETS_BASE_PATH)
    SSAT_SCOPE_OPENAI
  end

  sig do params(
    user: User,
    integration_id: String,
    session: T.nilable(UserSession),
    real_ip: T.nilable(String),
    token: T.nilable(T.any(Copilot::DecryptedToken, Copilot::EncryptedToken)),
    api_version: String
  ).void
  end
  def initialize(user, integration_id:, session:, real_ip:, token: nil, api_version: CopilotAPI::VERSION_DEFAULT)
    @user = user
    @integration_id = integration_id
    @session = session
    @real_ip = real_ip
    @token = token
    @api_version = api_version
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
    path = "/threads/#{thread_id}"
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
    path = "/threads/#{thread_id}"
    make_request(method: :delete, path: CopilotAPI::CHAT_BASE_PATH + path)
  end

  sig { params(thread_id: T.untyped).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess])) }
  def clear_thread(thread_id:)
    path = "/threads/#{thread_id}/clear"
    make_request(method: :patch, path: CopilotAPI::CHAT_BASE_PATH + path)
  end

  sig do params(
    thread_id: String,
    name: String,
    generate: T::Boolean,
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def update_thread_name(thread_id:, name: "", generate: true)
    path = "/threads/#{thread_id}/name"
    data = { name: name, generate: generate }
    make_request(method: :patch, path: CopilotAPI::CHAT_BASE_PATH + path, data: data)
  end

  sig do params(
    thread_id: String,
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def list_messages(thread_id:)
    path = "/threads/#{thread_id}/messages"
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
    path = "/threads/#{thread_id}/messages"
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

    path = "/threads/#{thread_id}/messages/#{message_id}/feedback"
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
    data = { model: model, prompt: [prompt], max_tokens: max_tokens, temperature: temperature, stop: stop }

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
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def async_create_completion(model:, prompt:, max_tokens:, temperature:, stop: [])
    data = { model: model, prompt: [prompt], max_tokens: max_tokens, temperature: temperature, stop: stop }
    make_request(
      async: true,
      path: "/completions",
      method: :post,
      data: data
    )
  end

  sig do params(
    model: String,
    messages: T::Array[T.untyped],
    max_tokens: Integer,
    temperature: Float,
    stop: T::Array[String],
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def create_chat_completion(model:, messages:, max_tokens:, temperature:, stop: [])
    data = { model: model, messages: messages, max_tokens: max_tokens, temperature: temperature, stop: stop }
    make_request(
      path: "/chat/completions",
      method: :post,
      data: data
    )
  end

  sig do params(
    model: String,
    messages: T::Array[T.untyped],
    max_tokens: Integer,
    temperature: Float,
    stop: T::Array[String]
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def async_create_chat_completion(model:, messages:, max_tokens:, temperature:, stop: [])
    data = { model: model, messages: messages, max_tokens: max_tokens,  temperature: temperature, stop: stop }
    make_request(
      async: true,
      path: "/chat/completions",
      method: :post,
      data: data
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

  sig do
    returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def list_knowledge_bases
    make_request(
      path: "/github/knowledge_bases",
      method: :get,
      integration_id: CopilotAPI::COPILOT_KNOWLEDGE_BASE_INTEGRATION_ID,
      query: {
        org_ids: authorized_org_ids
      }
    )
  end

  sig { params(org_id: Integer).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess])) }
  def list_org_knowledge_bases(org_id:)
    make_request(
      path: "/github/knowledge_bases/org/#{org_id}",
      method: :get,
      integration_id: CopilotAPI::COPILOT_KNOWLEDGE_BASE_INTEGRATION_ID
    )
  end

  sig do
    params(
      model: T.nilable(T::Hash[Symbol, T.untyped])
    ).returns(T.any(
      ActiveSupport::HashWithIndifferentAccess,
      ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]
    ))
  end
  def create_knowledge_base(model)
    make_request(
      path: "/github/knowledge_bases",
      method: :post,
      data: model,
      integration_id: CopilotAPI::COPILOT_KNOWLEDGE_BASE_INTEGRATION_ID
    )
  end

  sig do
    params(
      knowledge_base_id: String,
    ).returns(ActiveSupport::HashWithIndifferentAccess)
  end
  def get_knowledge_base(knowledge_base_id:)
    T.cast(make_request(
      path: "/github/knowledge_bases/#{knowledge_base_id}",
      method: :get,
      integration_id: CopilotAPI::COPILOT_KNOWLEDGE_BASE_INTEGRATION_ID,
    ), ActiveSupport::HashWithIndifferentAccess)
  end

  sig do
    params(
      knowledge_base_id: String,
      model: T::Hash[Symbol, T.untyped]
    ).returns(T.any(
      ActiveSupport::HashWithIndifferentAccess,
      ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]
    ))
  end
  def update_knowledge_base(knowledge_base_id, model)
    make_request(
      path: "/github/knowledge_bases/#{knowledge_base_id}",
      method: :patch,
      data: model,
      integration_id: CopilotAPI::COPILOT_KNOWLEDGE_BASE_INTEGRATION_ID
    )
  end

  sig do
    params(
      knowledge_base_id: String,
      repo_id: Integer,
      description: String,
      embeddings: T.any(String, T::Array[Float])
    ).returns(T.any(
      ActiveSupport::HashWithIndifferentAccess,
      ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]
    ))
  end
  def update_knowledge_base_repo_description(knowledge_base_id, repo_id, description, embeddings)
    make_request(
      path: "/github/knowledge_bases/#{knowledge_base_id}/sourcerepos/#{repo_id}/description",
      method: :patch,
      data: { description:, embeddings: },
      integration_id: CopilotAPI::COPILOT_KNOWLEDGE_BASE_INTEGRATION_ID
    )
  end

  sig { params(knowledge_base_id: String).returns(ActiveSupport::HashWithIndifferentAccess) }
  def delete_knowledge_base(knowledge_base_id:)
    T.cast(make_request(
      path: "/github/knowledge_bases/#{knowledge_base_id}",
      method: :delete,
      integration_id: CopilotAPI::COPILOT_KNOWLEDGE_BASE_INTEGRATION_ID
    ), ActiveSupport::HashWithIndifferentAccess)
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
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def create_code_review(role:, references:, experiment_headers:, interaction_id:, interaction_type:, initiator:)
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
      initiator:
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
    path = "agents/sessions/#{session_id}/logs"
    make_request(method: :get, path:, retry_401s: user.feature_enabled?("copilot_swe_agent_session_retry_401s"))
  end

  sig do params(
    resource_type: String,
    resource_id: Integer,
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def get_swe_agent_sessions(resource_type:, resource_id:)
    path = "agents/sessions/resource/#{resource_type}/#{resource_id}"
    make_request(method: :get, path:, retry_401s: user.feature_enabled?("copilot_swe_agent_session_retry_401s"))
  end

  sig do
    returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def list_user_swe_agent_sessions
    path = "agents/sessions"
    make_request(method: :get, path:)
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
  ).returns(T.any(ActiveSupport::HashWithIndifferentAccess, ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess]))
  end
  def make_request(method:, path:, async: false, data: nil, query: {}, integration_id: @integration_id, experiment_headers: {}, interaction_id: nil, interaction_type: nil, initiator: nil, retry_401s: false)
    CopilotAPI.make_request(async:, token:, integration_id:, method:, path:, data:, query:, user_id: user.id, real_ip:, experiment_headers:, interaction_id:, interaction_type:, initiator:, retry_401s:, copilot_api_version: @api_version)
  end

  sig { returns(T::Array[Integer]) }
  def authorized_org_ids
    cap_filter.authorized_resource_ids(user.organizations, only: :saml)
  end
end
