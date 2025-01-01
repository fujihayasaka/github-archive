# typed: strict
# frozen_string_literal: true

class Discussion::CopilotSummarizer
  include GitHub::Memoizer

  # Keep in sync with Hydro enum `github.discussions.v2.GiveCopilotSummaryFeedback.CopilotSummaryFeedbackChoice`
  DISCUSSION_SUMMARY_FEEDBACK_OPTIONS = T.let(%w[
    UNKNOWN
    UNHELPFUL
    INCORRECT
    POORLY_FORMATTED
    OFFENSIVE_OR_DISCRIMINATORY
    OTHER
    POSITIVE
  ].freeze, T::Array[String])

  DISCUSSION_SUMMARY_NEGATIVE_FEEDBACK_LABELS = T.let({
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

  # Default prompt for summarizing a discussion.
  # Users can override this with a custom prompt if they have the necessary permissions.
  # Used in Copilot API (packages/copilot/app/models/copilot/user/copilot_api.rb).
  USER_PROMPT = <<~MARKDOWN
    You will be given the headline, category, and labels of a discussion.
    Classify the discussion into one of the following categories:
    - Announcement
    - Feature request
    - Ask for help
    - Call for input
    - Decision/event documentation
    - General discussion

    Next, extract the relevant information from the discussion content and structure it based on the previous classification into one of the following formats.

    For Announcements, use this format:
    - **Overview:** [Key points of what was announced.]
    - **Themes:** [Overall response, sentiments, and feedback from comments.]
    - If the discussion is open: **Next Steps:** [Action items, open questions, or risks.]
    - If the discussion has been closed, answered, or both: **Outcome:** [Overview of what was resolved or answered. Include any remaining action items or open questions.]

    For Feature requests, use this format:
    - **Overview:** [Overview of the request from the current state. Include outcome, potential impact, and priority.]
    - **Proposals:** [Descriptions of most significant proposals with benefits, risks, feedback, and overall sentiment from the comments.]
    - If the discussion is open: **Next steps:** [Remaining action items, open questions, or potential solutions to resolve. Note status and any progress made.]
    - If the discussion has been closed, answered, or both: **Outcome:** [Overview of what was resolved or answered. Include any remaining work or open questions.]

    For Ask for help, use this format:
    - **Overview:** [Overview of what is being asked or encountered.]
    - **Impact:** [Impact this has, severity, and affected users/systems.]
    - If the discussion is open: **Next Steps:** [Remaining action items, open questions, or potential solutions to resolve. Note status and any progress made.]
    - If the discussion has been closed, answered, or both: **Outcome:** [Overview of what was resolved or answered. Include any remaining work or open questions.]

    For Calls for input, use this format:
    - **Overview:** [Central idea or problem discussed.]
    - **Proposals:** [Main trade offs, pros and cons, and sentiments of the suggested solutions and ideas.]
    - If the discussion is open: **Next steps:** [Identified or suggested solution, action items, or open questions.]
    - If the discussion has been closed, answered, or both: **Outcome:** [Overview of what was resolved or answered. Include any remaining work or open questions.]

    For Decision/event documentation, use this format:
    - **Recap:** [Overview of what has been done and the reasoning behind it.]
    - **Highlights:** [Key points, accomplishments, or progress.]
    - If the discussion is open: **Next steps:**  [Remaining action items, open questions, or potential risks.]
    - If the discussion has been closed, answered, or both: **Outcome:** [Overview of what was resolved or answered. Include any remaining work or open questions.]

    For General discussions and all other types, use this format:
    - **Overview:** [Overview of the discussion.]
    - **Key points:** [Most significant ideas or arguments presented.]
    - If the discussion is open: **Next steps:** [Remaining action items, open questions, or potential solutions. Note status and any progress made.]
    - If the discussion has been closed, answered, or both: **Outcome:** [Overview of what was resolved or answered. Include any remaining work or open questions.]

    In your own words, return only the extracted and formatted information in the structure described previously, and nothing else.
    - DO NOT use roman numerals for any list formatting.
    - DO NOT include the type of discussion in the response.
    - DO NOT include any notes in the response.
    - DO NOT repeat the headline in the response.
    - DO NOT repeat the content of the discussion in the response.
    - Use past tense if the discussion is closed or answered.
  MARKDOWN

  USER_PROMPT_VERSION = T.let(Digest::SHA256.hexdigest(USER_PROMPT), String)

  DATADOG_PREFIX = "discussions.copilot"

  sig { params(markdown: T.nilable(String), repository: T.nilable(Repository)).returns(String) }
  def self.process_markdown_for_summarization(markdown, repository:)
    GitHub::Goomba::CopilotSummaryInputPipeline.to_text(markdown || "", { entity: repository }, nil)
  end

  sig { params(discussion: Discussion, viewer: T.nilable(User)).returns(Promise[T::Boolean]) }
  def self.async_can_be_summarized?(discussion:, viewer:)
    return Promise.resolve(T.let(false, T::Boolean)) unless viewer&.copilot_discussion_summary_feature_enabled?

    copilot_user = Copilot::User.new(viewer)
    Promise.all([
      copilot_user.user_object.async_plan_subscription,
      copilot_user.async_orgs_using_copilot_for_business,
    ]).then do |_, copilot_orgs|
      biz_promises = copilot_orgs.map { |copilot_org| copilot_org.organization_object.async_business }
      Promise.all(biz_promises).then do
        can_be_summarized?(viewer: viewer, copilot_user: copilot_user, discussion: discussion)
      end
    end
  end

  sig do
    params(
      discussion: Discussion,
      viewer: T.nilable(User),
      copilot_user: T.nilable(T.any(Copilot::Public::User, Copilot::User)),
    ).returns(T::Boolean)
  end
  def self.can_be_summarized?(discussion:, viewer:, copilot_user: nil)
    return false unless viewer&.copilot_discussion_summary_feature_enabled?
    discussion_summarizer = new(discussion: discussion, actor: viewer)
    CopilotThreadSummarizer.can_be_summarized?(
      viewer: viewer,
      copilot_user: copilot_user,
      body_length: discussion_summarizer.body_length,
      get_comment_bodies_length: -> { discussion_summarizer.comment_bodies_length },
    )
  end

  sig { params(discussion: Discussion, actor: User).void }
  def initialize(discussion:, actor:)
    @discussion = discussion
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

  sig { returns(Integer) }
  def comment_count
    discussion.comment_count
  end

  sig do
    params(token: T.nilable(Copilot::EncryptedToken), prompt: T.nilable(String)).returns(CopilotSummaryAgentResponse)
  end
  def summarize(token: nil, prompt: nil)
    copilot_api = T.let(
      actor.copilot_api(integration_id: CopilotAPI::COPILOT_EMBEDDED_EXPERIENCE_INTEGRATION_ID, token: token),
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
      type: "github.discussion",
      id: discussion_id.to_s,
      data: copilot_api_reference_data,
    }
  end

  # Public: Returns a Hash that fits the shape of `reference.Discussion` type in
  # https://github.com/github/copilot-api/blob/91c6e84d3a12d5e57c6cd656948c80ca53b31bd4/pkg/chat/reference/discussion.go#L57-L76
  sig { returns T::Hash[Symbol, T.untyped] }
  def copilot_api_reference_data
    {
      type: "discussion", # https://github.com/github/copilot-api/blob/b26554bd359036519e5ea4afab3f074a3d5c0c32/pkg/chat/reference/reference.go#L108
      body: body_text,
      title: title,
      id: discussion_id,
      repository: repository_for_copilot_api,
      number: number,
      state: state,
      authorLogin: author_display_login,
      answer: chosen_comment_copilot_summarizer&.copilot_api_reference_data,
      comments: copilot_comment_summarizers.map(&:copilot_api_reference_data),
      totalUpvotes: total_upvotes,
      reactionCounts: reaction_counts_for_copilot_api,
      labels: labels_for_copilot_api,
      category: category_for_copilot_api,
      poll: poll_for_copilot_api,
    }
  end

  # Public: Emit an event indicating a user gave feedback about a discussion summary that was generated by Copilot.
  #
  # actor - the user who requested the summary
  # feedback_choices - the user's selection of which `DISCUSSION_SUMMARY_FEEDBACK_OPTIONS` values convey their
  #                    feedback about the summary
  # feedback_text - the user's own words about the summary
  # header_request_id - the X-Request-Id header of the original request sent to copilot-api
  #
  # Returns a Boolean indicating success.
  sig do
    params(
      feedback_choices: T::Array[String],
      feedback_text: T.nilable(String),
      header_request_id: T.nilable(String)
    ).returns(T::Boolean)
  end
  def instrument_copilot_summary_feedback(feedback_choices:, feedback_text: nil, header_request_id: nil)
    return false if feedback_choices.empty?

    invalid_feedback_choices = feedback_choices - DISCUSSION_SUMMARY_FEEDBACK_OPTIONS
    return false if invalid_feedback_choices.present?

    # Use `github_revision` to inspect the `USER_PROMPT` associated with the feedback:
    # https://github.com/github/github/blob/<github_revision>/packages/copilot_summaries/app/models/discussion/copilot_summarizer.rb
    # shows the prompt for the given version.
    # https://github.com/github/github/commits/<github_revision>/packages/copilot_summaries/app/models/discussion/copilot_summarizer.rb
    # shows the commit history for the prompt leading up to the given version.

    # Hydro
    GlobalInstrumenter.instrument "discussion.give_copilot_summary_feedback",
      analytics_tracking_id: actor.analytics_tracking_id,
      feedback_choice: feedback_choices,
      feedback: feedback_text,
      organization_id: organization_id,
      repository_id: repository_id,
      header_request_id: header_request_id,
      prompt_version: USER_PROMPT_VERSION,
      github_revision: GitHub.current_sha
    true
  end

  private

  sig { returns Discussion }
  attr_reader :discussion

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

  # Private: Returns a Hash to suit the structure of the `Repo` field in the `Discussion` type in copilot-api.
  # https://github.com/github/copilot-api/blob/ef95100895e125d4c807e5f9f3dc22e7eedd6cab/pkg/chat/reference/discussion.go#L50
  sig { returns T::Hash[Symbol, T.nilable(T.any(String, Integer))] }
  def repository_for_copilot_api
    # https://github.com/github/copilot-api/blob/6e63037b201294704eda3031beef16f57e453560/pkg/chat/reference/discussion.go#L12-L16
    { id: repository_id, name: repository&.name, owner: repository_owner_login }
  end

  # Private: Returns a list of labels to suit the structure of the `Labels` field in the `Discussion` type in
  # copilot-api. https://github.com/github/copilot-api/blob/e28abf0fe94107f4ccad13708c2c2407bc89756b/pkg/chat/reference/discussion.go#L59
  sig { returns T::Array[T::Hash[Symbol, T.nilable(String)]] }
  def labels_for_copilot_api
    discussion.labels.order(:lowercase_name).map do |label|
      # https://github.com/github/copilot-api/blob/e28abf0fe94107f4ccad13708c2c2407bc89756b/pkg/chat/reference/discussion.go#L39-L43
      { name: label.name, description: label.description }
    end
  end

  # Private: Returns a list of reaction counts to suit the structure of the `ReactionCounts` field in the `Discussion`
  # type in copilot-api. https://github.com/github/copilot-api/blob/e28abf0fe94107f4ccad13708c2c2407bc89756b/pkg/chat/reference/discussion.go#L60
  sig { returns T::Array[T::Hash[Symbol, T.any(String, Integer)]] }
  def reaction_counts_for_copilot_api
    reactions_count.map do |reaction, count|
      # https://github.com/github/copilot-api/blob/e28abf0fe94107f4ccad13708c2c2407bc89756b/pkg/chat/reference/discussion.go#L23-L27
      { reaction: reaction, count: count }
    end
  end

  # Private: Returns a category hash to suit the structure of the `Category` field in the `Discussion` type in
  # copilot-api. https://github.com/github/copilot-api/blob/ef95100895e125d4c807e5f9f3dc22e7eedd6cab/pkg/chat/reference/discussion.go#L62
  sig { returns T::Hash[Symbol, T.nilable(String)] }
  def category_for_copilot_api
    # https://github.com/github/copilot-api/blob/ef95100895e125d4c807e5f9f3dc22e7eedd6cab/pkg/chat/reference/discussion.go#L65-L69
    { name: category&.name || "none", description: category&.description }
  end

  # Private: Returns a poll hash to suit the structure of the `Poll` field in the `Discussion` type in copilot-api.
  sig { returns T.nilable(T::Hash[Symbol, T.nilable(String)]) }
  def poll_for_copilot_api
    poll = discussion.poll
    return unless poll

    options_for_copilot_api = poll.options.map do |poll_option|
      { option: poll_option.option, totalVotes: poll_option.discussion_poll_votes_count }
    end

    { question: poll.question, options: options_for_copilot_api }
  end

  # Private: Includes top-level comments and nested replies for providing to copilot-api for use in summarizing
  # the discussion. Comments are sorted in ascending chronological order.
  sig { returns T::Array[DiscussionComment] }
  def comments_for_copilot_summary
    new_comments_limit = copilot_summary_larger_context_enabled? ? NEWER_COMMENT_LIMIT : PREV_NEWER_COMMENT_LIMIT
    old_comments_limit = copilot_summary_larger_context_enabled? ? OLDER_COMMENT_LIMIT : PREV_OLDER_COMMENT_LIMIT

    should_limit_comments = if copilot_summary_send_all_comments_enabled?
      false
    else
      comment_count > (new_comments_limit + old_comments_limit)
    end

    comments_scope = discussion.comments.not_spammy.not_wiped.not_minimized

    if answered?
      comments_scope = comments_scope.where.not(id: discussion.chosen_comment_id)
    end
    oldest_comments = if should_limit_comments
      comments_scope.reorder(id: :asc).limit(new_comments_limit).to_a
    else
      comments_scope.to_a # default order by creation time is fine
    end
    newest_comments = if should_limit_comments
      comments_scope.reorder(id: :desc).limit(old_comments_limit).to_a
    else
      []
    end

    all_comments = oldest_comments + newest_comments
    GitHub::PrefillAssociations.prefill_associations(all_comments, :repository, available_records: [repository])
    all_comments.sort_by { |comment| [comment.created_at, comment.id] }
  end

  sig { returns T::Array[DiscussionComment::CopilotSummarizer] }
  memoize def copilot_comment_summarizers
    comments_for_copilot_summary.map do |comment|
      DiscussionComment::CopilotSummarizer.new(comment: comment, actor: actor)
    end
  end

  sig { returns T.nilable(DiscussionComment::CopilotSummarizer) }
  def chosen_comment_copilot_summarizer
    return unless answered?
    DiscussionComment::CopilotSummarizer.new(comment: T.must(chosen_comment), actor: actor)
  end

  sig { params(actor: User).void }
  def instrument_copilot_summarize(actor:)
    # Hydro
    GlobalInstrumenter.instrument "discussion.copilot_summarize",
      analytics_tracking_id: actor.try(:analytics_tracking_id),
      organization_id: organization_id,
      repository_id: repository_id,
      body_length: body_length,
      comment_bodies_length: comment_bodies_length,
      comment_count: comment_count
  end

  sig { returns Integer }
  def discussion_id
    discussion.id
  end

  sig { returns T.nilable(DiscussionComment) }
  def chosen_comment
    discussion.chosen_comment
  end

  sig { returns T.nilable(T::Boolean) }
  def answered?
    discussion.answered?
  end

  sig { returns(T.nilable(Integer)) }
  def organization_id
    discussion.organization_id
  end

  sig { returns(Integer) }
  def repository_id
    discussion.repository_id
  end

  sig { returns(T.nilable(Repository)) }
  def repository
    discussion.repository
  end

  sig { returns(String) }
  def author_display_login
    discussion.author_display_login
  end

  sig { returns(T.nilable(String)) }
  def repository_owner_login
    discussion.repository_owner_login
  end

  sig { returns String }
  memoize def body_text
    self.class.process_markdown_for_summarization(body, repository: repository)
  end

  sig { returns(String) }
  def body
    discussion.body || ""
  end

  sig { returns(T.nilable(DiscussionCategory)) }
  def category
    discussion.category
  end

  sig { returns(Integer) }
  def number
    discussion.number
  end

  sig { returns(Integer) }
  def total_upvotes
    discussion.total_upvotes
  end

  sig { returns T::Hash[String, Integer] }
  def reactions_count
    discussion.reactions_count
  end

  sig { returns(String) }
  def title
    discussion.title
  end

  sig { returns(String) }
  def state
    discussion.state
  end
end
