# typed: strict
# frozen_string_literal: true

class Issue::CopilotSummarizer
  include GitHub::Memoizer

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

  NEWER_COMMENT_LIMIT = 400
  OLDER_COMMENT_LIMIT = 100
  PREV_NEWER_COMMENT_LIMIT = 80
  PREV_OLDER_COMMENT_LIMIT = 20

  # Default prompt for summarizing an issue.
  # Users can override this with a custom prompt if they have the necessary permissions.
  # Used in Copilot API (packages/copilot/app/models/copilot/user/copilot_api.rb).
  USER_PROMPT = <<~MARKDOWN
    You will be given the headline, labels, and possibly the type of an issue.
    Using the information provided, classify the issue into one of the following categories:
    - Task
    - Bug
    - Feature request
    - Epic
    - General issue

    Next, extract the relevant information from the issue content, including any sub-issues, and structure it based on the previous classification into one of the following formats.

    For Tasks, use this format:
    - **Overview:** [Overview of the task, priority, and expected outcome. Include status and any progress made.]
    - **Scope:** [Scope and requirements.]
    - If the issue is open: **Next Steps:** [Remaining action items, open questions, sub-issues, or risks to complete.]
    - If the issue is closed: **Outcome:** [Overview of what was accomplished. Include any remaining work or open questions.]

    For Bugs, use this format:
    - **How to reproduce:** [Steps to trigger or reproduce the bug.]
    - **Impact:** [Impact this has, severity, and affected users/systems.]
    - If the issue is open: **Next Steps:** [Remaining action items, open questions, sub-issues, or potential solutions to complete. Note status and any progress made.]
    - If the issue is closed: **Outcome:** [Overview of what was accomplished. Include any remaining work or open questions.]

    For Feature requests, use this format:
    - **Overview:** [Overview of the request from the current state. Include outcome, potential impact, and priority.]
    - **Proposals:** [Descriptions of most significant proposals with benefits, risks, feedback, and overall sentiment.]
    - If the issue is open: **Next steps:** [Remaining action items, open questions, or potential solutions to complete. Note status and any progress made.]
    - If the issue is closed: **Outcome:** [Overview of what was accomplished. Include any remaining work or open questions.]

    For Epics, use this format:
    - **Goals:** [Goals and expected impact. Include timeline and progress towards completion.]
    - **Scope:** [Main components of work to be completed, summarize sub-issues if there are any.]
    - If the issue is open: **Related work:** [Prerequisites, dependencies, blockers, or risks. DO NOT include sub-issues.]
    - If the issue has been closed: **Outcome:** [Overview of what was achieved. Include any remaining related work or open questions.]

    For General issues, use this format:
    - **Overview:** [Overview of the issue.]
    - **Key points:** [Most significant ideas, fixes, or arguments presented.]
    - If the issue is open: **Next steps:** [Remaining action items, open questions, or risk to complete.]
    - If the issue is closed: **Outcome:** [Overview of what was done. Include any remaining related work or open questions.]

    In your own words, return only the extracted and formatted information in the structure described previously, and nothing else.
    - DO NOT use roman numerals for any list formatting.
    - DO NOT include the type of issue in the response.
    - DO NOT include any notes in the response.
    - DO NOT repeat the headline in the response.
    - DO NOT repeat any part of the issue content in the response.
    - Use past tense if the issue is closed.
  MARKDOWN

  USER_PROMPT_VERSION = T.let(Digest::SHA256.hexdigest(USER_PROMPT), String)

  DATADOG_PREFIX = "issues.copilot"

  sig { params(viewer: T.nilable(User)).returns(T::Boolean) }
  def self.feature_enabled?(viewer:)
    return false unless viewer
    viewer.feature_enabled?(:issues_copilot_summary) ||
      viewer.organizations.any? { |org| org.feature_enabled?(:issues_copilot_summary) }
  end

  sig { params(markdown: T.nilable(String), repository: T.nilable(Repository)).returns(String) }
  def self.process_markdown_for_summarization(markdown, repository:)
    # Do the same processing on issue text as we do for discussion text.
    Discussion::CopilotSummarizer.process_markdown_for_summarization(markdown, repository: repository)
  end

  sig do
    params(
      issue: Issue,
      viewer: T.nilable(User),
      copilot_user: T.nilable(T.any(Copilot::Public::User, Copilot::User)),
    ).returns(T::Boolean)
  end
  def self.can_be_summarized?(issue:, viewer:, copilot_user: nil)
    return false unless viewer && feature_enabled?(viewer: viewer)
    issue_summarizer = new(issue: issue, actor: viewer)
    CopilotThreadSummarizer.can_be_summarized?(
      viewer: viewer,
      copilot_user: copilot_user,
      body_length: issue_summarizer.body_length,
      get_comment_bodies_length: -> { issue_summarizer.comment_bodies_length },
    )
  end

  sig { params(issue: Issue, viewer: T.nilable(User)).returns(Promise[T::Boolean]) }
  def self.async_can_be_summarized?(issue:, viewer:)
    return Promise.resolve(T.let(false, T::Boolean)) unless viewer && feature_enabled?(viewer: viewer)

    copilot_user = Copilot::User.new(viewer)
    Promise.all([
      copilot_user.user_object.async_plan_subscription,
      copilot_user.async_orgs_using_copilot_for_business,
    ]).then do |_, copilot_orgs|
      biz_promises = copilot_orgs.map { |copilot_org| copilot_org.organization_object.async_business }
      Promise.all(biz_promises).then do
        can_be_summarized?(viewer: viewer, copilot_user: copilot_user, issue: issue)
      end
    end
  end

  sig { params(issue: Issue, actor: User).void }
  def initialize(issue:, actor:)
    @issue = issue
    @actor = actor
  end

  sig { returns Integer }
  def body_length
    body_text.length
  end

  sig { returns Integer }
  def comment_bodies_length
    copilot_comment_summarizers.sum(&:body_length)
  end

  sig { returns Integer }
  def comments_count
    issue.issue_comments_count || 0
  end

  sig { params(prompt: T.nilable(String)).returns(CopilotSummaryAgentResponse) }
  def summarize(prompt: nil)
    copilot_api = T.let(
      actor.copilot_api(integration_id: CopilotAPI::COPILOT_EMBEDDED_EXPERIENCE_INTEGRATION_ID),
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
      feedback_choices: T::Array[String],
      feedback_text: T.nilable(String),
      header_request_id: T.nilable(String)
    ).returns(T::Boolean)
  end
  def instrument_copilot_summary_feedback(feedback_choices:, feedback_text: nil, header_request_id: nil)
    return false if feedback_choices.empty?

    invalid_feedback_choices = feedback_choices - ISSUE_SUMMARY_FEEDBACK_OPTIONS
    return false if invalid_feedback_choices.present?

    # Use `github_revision` to inspect the `USER_PROMPT` associated with the feedback:
    # https://github.com/github/github/blob/<github_revision>/packages/copilot_summaries/app/models/issue/copilot_summarizer.rb
    # shows the prompt for the given version.
    # https://github.com/github/github/commits/<github_revision>/packages/copilot_summaries/app/models/issue/copilot_summarizer.rb
    # shows the commit history for the prompt leading up to the given version.
    GlobalInstrumenter.instrument "issue.give_copilot_summary_feedback",
      analytics_tracking_id: actor.analytics_tracking_id,
      feedback_choice: feedback_choices,
      feedback: feedback_text,
      organization_id: repository&.organization_id,
      repository_id: repository_id,
      header_request_id: header_request_id,
      prompt_version: USER_PROMPT_VERSION,
      github_revision: GitHub.current_sha

    true
  end

  # Public: Returns a Hash that fits the shape of `reference.Issue` type in copilot-api.
  # https://github.com/github/copilot-api/blob/3dd78e93904f9d61ef293ec8c5878fb42f89986e/pkg/chat/reference/issue.go#L18-L34
  sig { returns T::Hash[Symbol, T.untyped] }
  def copilot_api_reference_data
    result = {
      type: "issue", # https://github.com/github/copilot-api/blob/0b9fbb50dcc58caf489ca7f5cbf9a3040af7739b/pkg/chat/reference/reference.go#L87
      id: issue_id,
      number: number,
      repository: repository_for_copilot_api,
      title: title,
      body: body_text,
      state: state,
      authorLogin: safe_user.display_login,
      comments: copilot_comment_summarizers.map(&:copilot_api_reference_data),
      reactionCounts: reaction_counts_for_copilot_api,
      labels: labels_for_copilot_api,
      subIssues: sub_issues_for_copilot_api,
    }
    issue_type = issue.issue_type
    result[:issueType] = issue_type_for_copilot_api(issue_type) if issue_type
    result
  end

  private

  sig { returns Issue }
  attr_reader :issue

  sig { returns User }
  attr_reader :actor

  sig { returns(T::Boolean) }
  memoize def copilot_summary_larger_context_enabled?
    actor.feature_enabled?(:copilot_summary_larger_context)
  end

  sig { returns(T::Boolean) }
  memoize def copilot_summary_send_all_comments_enabled?
    actor.feature_enabled?(:copilot_summary_send_all_comments)
  end

  sig { returns User }
  def safe_user
    issue.safe_user
  end

  sig { returns Integer }
  def issue_id
    issue.id
  end

  sig { returns(T.nilable(Repository)) }
  def repository
    issue.repository
  end

  sig { returns(Integer) }
  def repository_id
    issue.repository_id
  end

  sig { returns String }
  memoize def body_text
    self.class.process_markdown_for_summarization(body, repository: repository)
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

  sig { returns T::Hash[String, Integer] }
  def reactions_count
    issue.reactions_count
  end

  # Private: Returns a list of labels to suit the structure of the `Labels` field in the `Issue` type in
  # copilot-api.
  # https://github.com/github/copilot-api/blob/9f0fb30b7c44be31f17ad762a64d35cbb9fed93b/pkg/chat/reference/issue.go#L55
  sig { params(issue: Issue).returns(T::Array[T::Hash[Symbol, T.nilable(String)]]) }
  def labels_for_copilot_api(issue = @issue)
    labels_limit = 10
    issue.labels.order(:lowercase_name).limit(labels_limit).map do |label|
      # https://github.com/github/copilot-api/blob/9f0fb30b7c44be31f17ad762a64d35cbb9fed93b/pkg/chat/reference/issue.go#L32-L36
      { name: label.name, description: label.description }
    end
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

  # Private: Returns a list of reaction counts to suit the structure of the `ReactionCounts` field in the `Issue`
  # type in copilot-api.
  # https://github.com/github/copilot-api/blob/9f0fb30b7c44be31f17ad762a64d35cbb9fed93b/pkg/chat/reference/issue.go#L56
  sig { returns T::Array[T::Hash[Symbol, T.any(String, Integer)]] }
  def reaction_counts_for_copilot_api
    reactions_count.map do |reaction, count|
      # https://github.com/github/copilot-api/blob/9f0fb30b7c44be31f17ad762a64d35cbb9fed93b/pkg/chat/reference/issue.go#L18-L22
      { reaction: reaction, count: count }
    end
  end

  # Private: Returns a list of sub-issues to suit the structure of the `SubIssues` field in the `Issue` type in copilot-api.
  # https://github.com/github/copilot-api/blob/91a72444ecc581fd717a44716be3e4224bcc4ef4/pkg/chat/reference/issue.go#L71
  sig { returns T::Array[T::Hash[Symbol, T.nilable(String)]] }
  def sub_issues_for_copilot_api
    issue.sub_issues.order(created_at: :asc).limit(5).map { |sub_issue| sub_issue_for_copilot_api(sub_issue) }
  end

  sig { params(sub_issue: Issue).returns(T::Hash[Symbol, T.nilable(String)]) }
  def sub_issue_for_copilot_api(sub_issue)
    # https://github.com/github/copilot-api/blob/81c0ff4398a984399f9d261d26dc7c35d4de154d/pkg/chat/reference/issue.go#L45-L50
    result = {
      title: sub_issue.title,
      url: sub_issue.url,
      labels: labels_for_copilot_api(sub_issue),
    }
    issue_type = sub_issue.issue_type
    result[:issueType] = issue_type_for_copilot_api(issue_type) if issue_type
    result
  end

  # Private: Returns an issue type to suit the structure of the `IssueType` field in the `Issue` type in copilot-api.
  # https://github.com/github/copilot-api/blob/91a72444ecc581fd717a44716be3e4224bcc4ef4/pkg/chat/reference/issue.go#L38-L42
  sig { params(issue_type: T.nilable(IssueType)).returns(T::Hash[Symbol, T.nilable(String)]) }
  def issue_type_for_copilot_api(issue_type)
    return {} if issue_type.nil?
    { name: issue_type.name, description: issue_type.description }
  end

  # Private: Includes comments on this issue for providing to copilot-api for use in summarizing the issue. Comments
  # are sorted in ascending chronological order.
  sig { returns T::Array[IssueComment] }
  def comments_for_copilot_summary
    new_comments_limit = copilot_summary_larger_context_enabled? ? NEWER_COMMENT_LIMIT : PREV_NEWER_COMMENT_LIMIT
    old_comments_limit = copilot_summary_larger_context_enabled? ? OLDER_COMMENT_LIMIT : PREV_OLDER_COMMENT_LIMIT

    should_limit_comments = if copilot_summary_send_all_comments_enabled?
      false
    else
      comments_count > (new_comments_limit + old_comments_limit)
    end

    comments_scope = issue.comments.not_spammy

    oldest_comments = if should_limit_comments
      comments_scope.reorder(id: :asc).limit(old_comments_limit).to_a
    else
      comments_scope.to_a # default order by creation time is fine
    end
    newest_comments = if should_limit_comments
      comments_scope.reorder(id: :desc).limit(new_comments_limit).to_a
    else
      []
    end
    all_comments = oldest_comments + newest_comments
    GitHub::PrefillAssociations.prefill_associations(all_comments, :repository, available_records: [repository])
    all_comments.sort_by { |comment| [comment.created_at, comment.id] }
  end

  sig { returns T::Array[IssueComment::CopilotSummarizer] }
  memoize def copilot_comment_summarizers
    comments_for_copilot_summary.map { |comment| IssueComment::CopilotSummarizer.new(comment: comment, actor: actor) }
  end

  sig { params(actor: User).void }
  def instrument_copilot_summarize(actor:)
    # Hydro
    GlobalInstrumenter.instrument "issue.copilot_summarize",
      analytics_tracking_id: actor.analytics_tracking_id,
      organization_id: repository&.organization_id,
      repository_id: repository_id,
      body_length: body_length,
      comment_bodies_length: comment_bodies_length,
      comments_count: comments_count
  end
end
