# typed: strict
# frozen_string_literal: true

class ReviewComments::Evaluators::Copilot < ReviewComments::AutomatedReviewCommentEvaluator

  FEEDBACK_OPTIONS = T.let({
    OFFENSIVE_OR_DISCRIMINATORY: "Comment is harmful or unsafe",
    POORLY_FORMATTED: "Comment is poorly formatted",
    INCORRECT: "Comment is not true",
    UNHELPFUL: "Comment is not helpful",
    INCORRECT_LINE: "Comment is attached to the wrong line(s)",
    DUPLICATE: "Comment is a duplicate of another comment",
    SUGGESTION_OFFENSIVE_OR_DISCRIMINATORY: "Code suggestion is harmful or unsafe",
    SUGGESTION_POORLY_FORMATTED: "Code suggestion is poorly formatted",
    SUGGESTION_UNHELPFUL: "Code suggestion does not solve the problem in the comment",
    SUGGESTION_INVALID: "Code suggestion is invalid",
  }, T::Hash[Symbol, String])

  sig do
    override.params(
      comment: AutomatedReviewComment,
      user: User,
      feedback: Symbol,
      choices: T::Array[Symbol],
      text_response: T.nilable(String),
    ).void
  end
  def feedback(comment:, user:, feedback:, choices:, text_response:)
    # TODO: Cleanup the comments. I've ported this code from app/controllers/copilot/code_review_feedback_controller.rb
    # but kept the old variable names inside the comments for easier comparison. Once the CCR team takes over and are familiar with it, they can clean this up.

    comment_id = comment.pull_request_review_comment_id.to_s # instead of params[:comment_id]
    current_user = user
    current_repository = @repository

    pull_request_id = comment.pull_request_id

    custom_instructions_included = PullRequests::Copilot::CodeReviewComment.where(
      subject_id: comment_id,
      subject_type: "PullRequestReviewComment"
    ).where.not(copilot_instruction_type: nil).exists?

    PullRequests::Copilot::instrument_code_review_feedback(
      request_id: nil, #GitHub.context[:request_id],
      organization_id: Organization.find_by(login: user.id)&.id, #(login: params[:user_id])&.id,
      repository_id: current_repository.id,
      pull_request_id: pull_request_id,
      comment_id: comment_id,
      analytics_tracking_id: current_user.analytics_tracking_id,
      feedback: feedback.to_s, #params[:feedback],
      feedback_choice: choices.map { |c| c.to_s }, #params[:feedback_choice],
      text_response: text_response, #params[:text_response],
      custom_instructions_included: custom_instructions_included,
      copilot_access_type: Copilot::Public::User.new(current_user).access_type,
    )

    if current_repository.feature_enabled_for_repo_or_owner?(:copilot_coding_guidelines) || current_user.feature_flag_enabled?(:copilot_coding_guidelines, default: false)
      code_review_comment = \
        PullRequests::Copilot::CodeReviewComment.where.not(
          copilot_coding_guideline_id: nil
        ).find_by(
          subject_type: "PullRequestReviewComment",
          subject_id: comment_id
        )

      if code_review_comment
        feedback = PullRequests::Copilot::CodeReviewCommentFeedback.build(
          repository: current_repository,
          code_review_comment: code_review_comment,
          feedback_author_id: current_user.id,
          feedback_type: feedback.to_s.downcase, #params[:feedback].downcase,
          text_response: text_response, #params[:text_response],
        )
        # params[:feedback_choice]&.each do |choice|
        choices.each do |choice|
          feedback.feedback_choices.build(repository: current_repository, choice: choice.to_s.downcase)
        end

        begin
          feedback.save!
        rescue ActiveRecord::RecordInvalid => e
          GitHub.logger.error(
            "Failed to save Copilot code review feedback",
            repository_id: current_repository.id,
            comment_id: comment_id,
            user_id: current_user.id,
            error: e.message
          )
        end
      end
    end
  end

  sig do
    override.params(
      comment: AutomatedReviewComment,
    ).returns(T::Boolean)
  end
  def show_feedback_buttons?(comment:)
    true
  end

  sig { override.returns(T::Array[{ value: String, label: String }]) }
  def feedback_options
    FEEDBACK_OPTIONS.map do |value, label|
      { value: value.to_s, label: label }
    end
  end

  sig do
    override.params(
      comment: AutomatedReviewComment,
    ).returns(T::Boolean)
  end
  def show_ai_note?(comment:)
    true
  end

  sig do
    override.params(
      comment: AutomatedReviewComment,
      user: User,
      pull: PullRequest,
    ).void
  end
  def apply_suggestion(comment:, user:, pull:)
    pr_review_comment = comment.pull_request_review_comment
    return if pr_review_comment.nil?

    thread = pr_review_comment.pull_request_review_thread
    thread&.resolve(resolver: user) unless thread&.resolved?
  end

  sig do
    override.params(
      ar_comment: AutomatedReviewComment,
      pull_request: T.untyped,
      pull_request_review_comment: T.untyped,
      user: T.nilable(User),
    ).returns(T::Boolean)
  end
  def show_apply_changes_button?(ar_comment:, pull_request:, pull_request_review_comment:, user:)
    return false unless user
    # When a suggestion diff already exists, the "Apply Suggestion" flow is used instead.
    return false unless ar_comment.suggestion_state_no_suggestion?

    PullRequests::Copilot::ApplyChangesHelper.can_apply_changes?(
      comment: pull_request_review_comment,
      pull_request: pull_request,
      user: user,
    )
  end
end
