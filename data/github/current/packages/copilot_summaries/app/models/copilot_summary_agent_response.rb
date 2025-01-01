# typed: strict
# frozen_string_literal: true

# Public: Represents a response from the Copilot API for a summary request.
#
# Mirrors `azuremodel.ChatCompletions` in github/copilot-api
# https://github.com/github/copilot-api/blob/31ba8a9e45ba9696fedbe580b706a6cd175b414c/pkg/azure/azuremodel/models.go#L24
class CopilotSummaryAgentResponse
  include GitHub::Memoizer

  class CopilotChatMessage < T::Struct
    const :id, T.nilable(String)
    const :intent, T.nilable(String)
    const :role, String
    const :content, T.nilable(String)
    const :created_at, T.nilable(String)
    const :thread_id, T.nilable(String)
    const :error, T.nilable(T.any(String, T::Hash[String, String]))
    const :references, T.nilable(T::Array[ActiveSupport::HashWithIndifferentAccess])
    const :skill_executions, T.nilable(T::Array[ActiveSupport::HashWithIndifferentAccess])
    const :copilot_annotations, T.nilable(ActiveSupport::HashWithIndifferentAccess)
    const :interrupted, T.nilable(T::Boolean)
    const :confirmations, T.nilable(T::Array[ActiveSupport::HashWithIndifferentAccess])
    const :client_confirmations, T.nilable(T::Array[ActiveSupport::HashWithIndifferentAccess])
    const :agent_errors, T.nilable(T::Array[ActiveSupport::HashWithIndifferentAccess])

    sig { params(message: ActiveSupport::HashWithIndifferentAccess).returns(CopilotChatMessage) }
    def self.from(message)
      new(
        id: message[:id],
        intent: message[:intent],
        role: message[:role],
        content: message[:content],
        created_at: message[:created_at],
        thread_id: message[:thread_id],
        error: message[:error],
        references: message[:references],
        skill_executions: message[:skill_executions],
        copilot_annotations: message[:copilot_annotations],
        interrupted: message[:interrupted],
        confirmations: message[:confirmations],
        client_confirmations: message[:client_confirmations],
        agent_errors: message[:agent_errors]
      )
    end
  end

  class Choice < T::Struct
    const :content_filter_results, ActiveSupport::HashWithIndifferentAccess
    const :finish_reason, String
    const :index, Integer
    const :message, CopilotChatMessage

    sig { params(choice: ActiveSupport::HashWithIndifferentAccess).returns(Choice) }
    def self.from(choice)
      new(
        content_filter_results: choice[:content_filter_results],
        message: CopilotChatMessage.from(choice[:message]),
        finish_reason: choice[:finish_reason],
        index: choice[:index]
      )
    end
  end

  sig do
    params(result: T.any(ActiveSupport::HashWithIndifferentAccess,
      ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess])
    ).returns(CopilotSummaryAgentResponse)
  end
  def self.from(result)
    new(
      choices: result[:choices].map { |choice| Choice.from(choice) },
      created: result[:created],
      usage: result[:usage],
      prompt_filter_results: result[:prompt_filter_results],
      copilot_references: result[:copilot_references],
      model: result[:model],
      id: result[:id],
      raw_json_response: result.to_hash
    )
  end

  sig do
    params(
      choices: T::Array[CopilotSummaryAgentResponse::Choice],
      created: Integer,
      usage: ActiveSupport::HashWithIndifferentAccess,
      prompt_filter_results: T::Array[ActiveSupport::HashWithIndifferentAccess],
      copilot_references: T::Array[ActiveSupport::HashWithIndifferentAccess],
      model: String,
      id: String,
      raw_json_response: T::Hash[String, T.untyped]
    )
    .void
  end
  def initialize(choices:, created:, usage:, prompt_filter_results:, copilot_references:, model:, id:, raw_json_response:)
    @choices = choices
    @created = created
    @usage = usage
    @prompt_filter_results = prompt_filter_results
    @copilot_references = copilot_references
    @model = model
    @id = id
    @raw_json_response = raw_json_response
  end

  sig { returns(T::Array[CopilotSummaryAgentResponse::Choice]) }
  attr_reader :choices

  sig { returns(Integer) }
  attr_reader :created

  sig { returns(T::Array[ActiveSupport::HashWithIndifferentAccess]) }
  attr_reader :copilot_references

  sig { returns(String) }
  attr_reader :model, :id

  sig { returns(T::Hash[String, T.untyped]) }
  attr_reader :raw_json_response

  sig { returns T.nilable(Integer) }
  def completion_token_usage
    usage["completion_tokens"]
  end

  sig { returns T.nilable(Integer) }
  def prompt_token_usage
    usage["prompt_tokens"]
  end

  sig { returns T.nilable(Integer) }
  def total_token_usage
    usage["total_tokens"]
  end

  sig { returns(T.nilable(String)) }
  memoize def summary
    choices.first&.message&.content
  end

  # Public: Returns the summary Copilot generated, rendered as HTML.
  #
  # viewer - the user who will view the summary
  # repository - the repository containing the content that Copilot summarized
  #
  # Returns an HTML string.
  sig do
    params(
      viewer: T.nilable(User),
      repository: T.nilable(Repository),
      cap_filter: ConditionalAccess::Web::Filter
    ).returns(T.nilable(String))
  end
  def summary_html(viewer:, repository:, cap_filter:)
    return nil unless summary
    context = {
      current_user: viewer,
      base_url: GitHub.url,
      entity: repository,
      unfurl_references: true,
      cap_filter: cap_filter,
    }
    context[:organization] = repository.organization if repository
    summary_html = GitHub::Goomba::MarkdownPipeline.to_html(summary, context, nil)
    if render_staff_html_comment?(viewer)
      json_str = CGI.escapeHTML(JSON.pretty_generate(raw_json_response))
      json_str_without_quotes = json_str.gsub("&quot;", '"')
      summary_html += "\n<!-- copilot-api response:\n\n#{json_str_without_quotes}\n\n-->".html_safe # rubocop:disable Rails/OutputSafety
    end
    summary_html
  end

  private

  sig { returns(ActiveSupport::HashWithIndifferentAccess) }
  attr_reader :usage

  sig { params(viewer: T.nilable(User)).returns(T::Boolean) }
  def render_staff_html_comment?(viewer)
    return false unless viewer&.feature_enabled?(:copilot_summary_custom_prompt)
    viewer.site_admin? || viewer.employee?
  end
end
