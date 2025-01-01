# typed: strict
# frozen_string_literal: true

class Issue::CopilotSummarizer
  extend T::Sig

  # Keep in sync with Hydro enum `github.v1.GiveCopilotIssueSummaryFeedback.CopilotSummaryFeedbackChoice`
  ISSUE_SUMMARY_FEEDBACK_OPTIONS = T.let(%w[
    UNKNOWN
    UNHELPFUL
    INCORRECT
    POORLY_FORMATTED
    OFFENSIVE_OR_DISCRIMINATORY
    OTHER
    POSITIVE
  ].freeze, T::Array[String])

  ISSUE_SUMMARY_NEGATIVE_FEEDBACK_LABELS = T.let({
    "UNHELPFUL" => "Not helpful",
    "INCORRECT" => "Incorrect",
    "POORLY_FORMATTED" => "Poorly formatted",
    "OFFENSIVE_OR_DISCRIMINATORY" => "Offensive or discriminatory",
    "OTHER" => "Other",
  }.freeze, T::Hash[String, String])

  # Default prompt for summarizing an issue.
  # Users can override this with a custom prompt if they have the necessary permissions.
  # Used in Copilot API (packages/copilot/app/models/copilot/user/copilot_api.rb).
  # Update `USER_PROMPT_VERSION` to be the commit SHA for this change whenever updating the prompt string
  USER_PROMPT = <<~MARKDOWN
    Create a concise summary for an issue thread to help users quickly understand the key points without reading the entire conversation.

    Use an unordered list with 3 bullet points. Use `**` for bold keywords.

    Structure as follows:

    - **Overview:** Summarize issue body.
    - **Key Points:** Highlight main themes or recurring topics.
    - **Next Steps:** List specific action items, open questions, or risks if applicable.
  MARKDOWN

  # The commit SHA in which the `USER_PROMPT` string was last modified
  #
  # https://github.com/github/github/blob/<USER_PROMPT_VERSION>/packages/issues/app/models/issue/copilot_dependency.rb#L34
  # is the prompt for the given version
  USER_PROMPT_VERSION = "b801aaf853ee8"

  DATADOG_PREFIX = "issues.copilot"

  sig { params(issue: Issue).void }
  def initialize(issue:)
    @issue = issue
  end

  sig do
    params(
      actor: User,
      token: Copilot::EncryptedToken,
      prompt: T.nilable(String)
    ).returns(CopilotSummaryAgentResponse)
  end
  def summarize(actor:, token:, prompt: nil)
    copilot_api = T.let(
      actor.copilot_api(integration_id: CopilotAPI::COPILOT_CHAT_INTEGRATION_ID, token: token),
      Copilot::User::CopilotApi
    )
    raw_response = copilot_api.summarize(references: [copilot_api_reference], custom_prompt: prompt,
      default_prompt: USER_PROMPT)
    instrument_copilot_summarize(actor: actor)
    summary_response = CopilotSummaryAgentResponse.from(raw_response)
    count_copilot_summary_token_usage(summary_response)
    summary_response
  end

  # Public: Returns a Hash that fits the shape of `agentprompt.Reference` type in
  # https://github.com/github/copilot-api/blob/fa44afed1877246702f0325a38a91128fe642514/pkg/agent/agentprompt/reference.go#L11-L17
  sig { returns T::Hash[Symbol, T.untyped] }
  def copilot_api_reference
    {
      type: "github.issue",
      id: issue_id.to_s,
      data: copilot_api_reference_data,
    }
  end

  sig do
    params(
      actor: User,
      feedback_choices: T::Array[String],
      feedback_text: T.nilable(String),
      header_request_id: T.nilable(String)
    ).returns(T::Boolean)
  end
  def instrument_copilot_summary_feedback(actor:, feedback_choices:, feedback_text: nil, header_request_id: nil)
    return false if feedback_choices.empty?

    invalid_feedback_choices = feedback_choices - ISSUE_SUMMARY_FEEDBACK_OPTIONS
    return false if invalid_feedback_choices.present?

    GlobalInstrumenter.instrument "issue.give_copilot_summary_feedback",
      analytics_tracking_id: actor.analytics_tracking_id,
      feedback_choice: feedback_choices,
      feedback: feedback_text,
      organization_id: repository&.organization_id,
      repository_id: repository_id,
      header_request_id: header_request_id,
      prompt_version: USER_PROMPT_VERSION

    true
  end

  # Public: Returns a Hash that fits the shape of `reference.Issue` type in copilot-api.
  # https://github.com/github/copilot-api/blob/3dd78e93904f9d61ef293ec8c5878fb42f89986e/pkg/chat/reference/issue.go#L18-L34
  sig { returns T::Hash[Symbol, T.untyped] }
  def copilot_api_reference_data
    {
      type: "issue", # https://github.com/github/copilot-api/blob/0b9fbb50dcc58caf489ca7f5cbf9a3040af7739b/pkg/chat/reference/reference.go#L87
      id: issue_id,
      number: number,
      repo: repository_for_copilot_api,
      title: title,
      body: GitHub::Goomba::CopilotSummaryPipeline.to_text(body),
      state: state,
      authorLogin: safe_user.display_login,
    }
  end

  private

  sig { returns Issue }
  attr_reader :issue

  sig { returns User }
  def safe_user
    issue.safe_user
  end

  sig { returns Integer }
  def issue_id
    T.must(issue.id)
  end

  sig { returns(T.nilable(Repository)) }
  def repository
    issue.repository
  end

  sig { returns(Integer) }
  def repository_id
    issue.repository_id
  end

  sig { returns(String) }
  def body
    issue.body || ""
  end

  sig { returns T.nilable(Integer) }
  def number
    issue.number
  end

  sig { returns T.nilable(String) }
  def title
    issue.title
  end

  sig { returns T.nilable(String) }
  def state
    issue.state
  end

  sig { params(summary_response: CopilotSummaryAgentResponse).void }
  def count_copilot_summary_token_usage(summary_response)
    total_tokens = summary_response.total_token_usage
    completion_tokens = summary_response.completion_token_usage
    prompt_tokens = summary_response.prompt_token_usage
    tags = ["model:#{summary_response.model}"]
    metric = "#{DATADOG_PREFIX}.summarize.tokens_used"

    if completion_tokens && completion_tokens > 0
      GitHub.dogstats.distribution(metric, completion_tokens, tags: tags + ["usage_type:completion"])
    end
    if prompt_tokens && prompt_tokens > 0
      GitHub.dogstats.distribution(metric, prompt_tokens, tags: tags + ["usage_type:prompt"])
    end
  end

  sig { returns T::Hash[Symbol, T.untyped] }
  def repository_for_copilot_api
    # https://github.com/github/copilot-api/blob/0b9fbb50dcc58caf489ca7f5cbf9a3040af7739b/pkg/chat/reference/issue.go#L11-L16
    { id: repository_id, name: repository&.name, owner: repository&.owner_display_login }
  end

  sig { params(actor: User).void }
  def instrument_copilot_summarize(actor:)
    # Hydro
    GlobalInstrumenter.instrument "issue.copilot_summarize",
      analytics_tracking_id: actor.analytics_tracking_id,
      organization_id: repository&.organization_id,
      repository_id: repository_id
  end
end
