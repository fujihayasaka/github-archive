# typed: strict
# frozen_string_literal: true

class AutomatedReviewComment < ApplicationRecord::Domain::IssuesPullRequests
  class Error < StandardError; end
  class PermissionError < Error; end
  class ArgumentError < Error; end
  class UnprocessableError < Error; end

  RESOLUTION_NOTE_MAX_LENGTH = 280

  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain legacy_return_type: true
  belongs_to :pull_request
  belongs_to :pull_request_review_comment

  enum :source, {
    source_code_quality:  0,
    source_code_scanning: 1,
    source_license_compliance: 2,
    source_copilot: 3,
  }

  enum :severity, {
    severity_none:  0,
    severity_note:  1,
    severity_warning: 2,
    severity_error: 3,
  }

  enum :security_severity, {
    security_severity_none:  0,
    security_severity_low: 1,
    security_severity_medium: 2,
    security_severity_high: 3,
    security_severity_critical: 4,
  }

  attribute :title, StringFromBinary.new
  attribute :message, StringFromBinary.new

  enum :suggestion_state, {
    suggestion_state_no_suggestion: 0,
    suggestion_state_pending: 1,
    suggestion_state_present: 2,
    suggestion_state_error: 3,
    suggestion_state_applied: 4
  }

  sig { returns(String) }
  def suggestion_state
    state = read_attribute(:suggestion_state)
    return state unless state == "suggestion_state_present"

    return "suggestion_state_outdated" if suggestion&.commit_sha != pull_request_review_comment&.pull_request&.head_sha
    state
  end

  sig { returns(T.nilable(ReviewComments::Suggestion)) }
  def suggestion
    suggestion_hash = read_attribute(:suggestion)
    return nil if suggestion_hash.blank?

    commit_sha = T.let(suggestion_hash["commit_sha"].presence || "", String)
    files = T.let([], T::Array[ReviewComments::Suggestion::File])
    suggestion_hash["files"].each do |file|
      files.append(ReviewComments::Suggestion::File.new(
        path: file["path"],
        diff_content: file["diff_content"]
      ))
    end

    ReviewComments::Suggestion.new(commit_sha:, files:)
  end

  sig { returns(String) }
  def format_body
    comment_body = []
    comment_body << "## #{ title }" if title.present?
    comment_body << "#{ message }" if message.present?
    comment_body.join("\n\n")
  end

  sig { returns(T::Boolean) }
  def fixed?
    fixed_at.present?
  end

  sig { returns(T::Boolean) }
  def dismissed?
    dismissal_reason.present?
  end

  sig { returns(T::Boolean) }
  def dismissable?
    evaluator_instance = evaluator
    return false if evaluator_instance.nil?

    evaluator_instance.dismissable?
  end

  sig { params(user: User).returns(T::Boolean) }
  def can_dismiss?(user:)
    if !review_thread.resolved? # the thread could already be resolved if the comment is fixed
      return false unless review_thread.async_can_resolve(user).sync
    end

    evaluator_instance = evaluator
    return false if evaluator_instance.nil?

    evaluator_instance.can_dismiss?(user:)
  end

  sig do
    params(
      user: User,
      reason: String,
      resolution_note: T.nilable(String)
    ).void
  end
  def dismiss!(user:, reason:, resolution_note:)
    raise UnprocessableError if dismissed?
    raise PermissionError unless can_dismiss?(user:)

    evaluator_instance = T.must(evaluator)
    evaluator_instance.dismiss(
      comment: self,
      user: user,
      reason: reason,
      resolution_note: resolution_note
    )

    self.dismissal_reason = reason
    self.dismissed_at = Time.now
    save!

    resolve_conversation!(user:)
  end

  sig { params(user: User).returns(T::Boolean) }
  def can_reopen?(user:)
    return false unless review_thread.async_can_unresolve(user).sync

    evaluator_instance = evaluator
    return false if evaluator_instance.nil?

    evaluator_instance.can_reopen?(user:)
  end

  sig do
    params(
      user: User,
    ).void
  end
  def reopen!(user:)
    raise UnprocessableError unless dismissed?
    raise PermissionError unless can_reopen?(user:)

    evaluator_instance = T.must(evaluator)
    evaluator_instance.reopen(
      comment: self,
      user: user,
    )

    self.dismissal_reason = nil
    self.dismissed_at = nil
    save!

    unresolve_conversation!(user:) if !fixed? # If it's fixed, the thread should stay resolved
  end

  sig { returns(T::Boolean) }
  def has_suggestion?
    valid_state = suggestion_state.in?(%w[
        suggestion_state_present
        suggestion_state_applied
      ])
    valid_state && suggestion.present?
  end

  sig do
    params(
      user: User,
      commit_message: String
    ).void
  end
  def apply_suggestion!(user:, commit_message: "")
    raise UnprocessableError unless suggestion_state != "suggestions_state_present"
    raise UnprocessableError if suggestion.nil?

    pr_review_comment = T.must(pull_request_review_comment)
    pr = T.must(pull_request)

    begin
      suggested_change = DiffEntrySuggestedChange.new(
        repository: T.must(repository),
        pull_request: pr,
        diff_entries: suggestion&.diff_entries
      )

      default_commit_message = "Potential fix for pull request finding"
      default_commit_message += ": #{title}" if title.present?
      co_author_note = "Co-authored-by: Copilot Autofix powered by AI <#{pr_review_comment.user&.git_author_email}>"

      suggested_change.commit_change_for_user(
        author: user,
        current_oid: pr.head_sha,
        message: commit_message.presence || default_commit_message,
        sign: true,
        co_author_note: co_author_note,
        reflog_data: {
          repo_name: suggested_change.repository.name_with_display_owner,
          repo_public: suggested_change.repository.public?,
          user_login: user.display_login,
          from: GitHub.context[:from],
          via: "automated review comment suggestion",
        }
      )
    rescue ReviewComments::Suggestion::ParseError => e
      # report the error to Sentry
      Failbot.report!(e)
      raise UnprocessableError.new(e.message)
    rescue DiffEntrySuggestedChange::ForbiddenError => e
      raise PermissionError
    rescue DiffEntrySuggestedChange::NotFoundError => e
      raise UnprocessableError.new(e.message)
    rescue DiffEntrySuggestedChange::UnprocessableError => e
      raise UnprocessableError.new(e.message)
    end

    # Wrap this in a transition together with the actual commit creation ^?
    suggestion_state_applied!
    evaluator&.apply_suggestion(comment: self, user:, pull: pr)

    # Example on how to do the telemetry events:
    # GlobalInstrumenter.instrument("automated_review_comment.suggestion_event", {
    #   repository_id: repository.id,
    #   pull_request_id: pull_request.id,
    #   pull_request_number: pull_request.number,
    #   review_comment_id: review_comment_id,
    #   automated_review_comment_id: id,
    #   type: type,
    #   resource_id: resource_id,
    #   event_type: :SUGGESTION_EVENT_TYPE_APPLIED,
    # })
  end

  sig do
    params(
      user: User,
      feedback: Symbol,
      choices: T::Array[Symbol],
      text_response: T.nilable(String),
    ).void
  end
  def feedback!(user:, feedback:, choices:, text_response:)
    raise ArgumentError, "feedback should be positive or negative" unless [:POSITIVE, :NEGATIVE].include?(feedback)
    raise ArgumentError, "no choice must be selected if feedback is positive" if feedback == :POSITIVE && choices.present?
    raise ArgumentError, "a choice must be selected if feedback is negative" if feedback == :NEGATIVE && choices.empty?
    raise ArgumentError, "invalid feedback choice" unless choices.all? { |choice| feedback_options_values.include?(choice) }

    payload = {
      repository_id: repository_id,
      automated_review_comment_id: id,
      pull_request_id: pull_request_id,
      pull_request_number: pull_request&.number,
      pull_request_review_comment_id: pull_request_review_comment_id,
      source: read_attribute_before_type_cast(:source),
      source_name: source,
      resource_id: resource_id,
      type: feedback,
      choice: choices,
      text_response: text_response,
    }
    GlobalInstrumenter.instrument("automated_review_comments.suggestion_feedback", payload)

    evaluator&.feedback(comment: self, user:, feedback:, choices:, text_response:)
  end

  sig { void }
  def fix!
    self.fixed_at = Time.now
    save!

    user = T.must(pull_request_review_comment&.user)

    resolve_conversation!(user: user)
  end

  sig { returns(T::Boolean) }
  def show_feedback_buttons?
    evaluator&.show_feedback_buttons?(comment: self) || false
  end

  sig { returns(T::Array[{ value: String, label: String }]) }
  def feedback_options
    evaluator&.feedback_options || []
  end

  sig { returns(T::Array[Symbol]) }
  def feedback_options_values
    feedback_options.map { |option| option[:value].to_sym }
  end

  sig { returns(T::Array[{ value: String, label: String, description: String }]) }
  def dismissal_options
    evaluator&.dismissal_options || []
  end

  sig { returns(T::Array[Symbol]) }
  def dismissal_options_values
    dismissal_options.map { |option| option[:value].to_sym }
  end

  private

  sig { returns(T.nilable(ReviewComments::AutomatedReviewCommentEvaluator)) }
  def evaluator
    return @evaluator if @evaluator

    @evaluator ||= T.let(nil, T.nilable(ReviewComments::AutomatedReviewCommentEvaluator))
    @evaluator = case source
    when "source_code_quality"
      ReviewComments::Evaluators::CodeQuality.new(T.must(repository))
    when "source_code_scanning"
      ReviewComments::Evaluators::CodeScanning.new(T.must(repository))
    when "source_license_compliance"
      ReviewComments::Evaluators::LicenseCompliance.new(T.must(repository))
    else
      nil
    end
  end

  sig do
    params(
      user: User
    ).void
  end
  def resolve_conversation!(user:)
    review_thread.resolve(resolver: user)
  end

  sig do
    params(
      user: User
    ).void
  end
  def unresolve_conversation!(user:)
    review_thread.unresolve(unresolver: user)
  end

  sig { returns(PullRequestReviewThread) }
  def review_thread
    T.must(pull_request_review_comment&.pull_request_review_thread)
  end
end
