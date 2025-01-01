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
  }

  enum :severity, {
    severity_note:  0,
    severity_warning: 1,
    severity_error: 2,
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

  sig { returns(T.nilable(ReviewComments::Suggestion)) }
  def suggestion
    suggestion_hash = read_attribute(:suggestion)
    return nil if suggestion_hash.blank?

    description = T.let(suggestion_hash["description"].presence || "", String)
    files = T.let([], T::Array[ReviewComments::Suggestion::File])
    suggestion_hash["files"].each do |file|
      files.append(ReviewComments::Suggestion::File.new(
        path: file["path"],
        diff_content: file["diff_content"]
      ))
    end

    ReviewComments::Suggestion.new(description: description, files: files)
  end

  sig { returns(String) }
  def format_body
    comment_body = []
    comment_body << "## #{ title }" if title.present?
    comment_body << "#{ message }" if message.present?
    comment_body.join("\n\n")
  end

  sig { returns(T::Boolean) }
  def dismissed?
    dismissal_reason.present?
  end

  sig { params(user: User).returns(T::Boolean) }
  def can_dismiss?(user:)
    return false unless review_thread.async_can_resolve(user).sync

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

    unresolve_conversation!(user:)
  end

  sig do
    params(
      user: User,
      commit_message: String
    ).void
  end
  def apply_suggestion!(user:, commit_message: "")
    raise UnprocessableError unless suggestion_state_present?
    raise UnprocessableError if suggestion.nil?

    # This should not be needed once out of KV
    pr_review_comment = PullRequestReviewComment.find_by(id: pull_request_review_comment_id)
    raise UnprocessableError if pr_review_comment.nil?
    pull_request = pr_review_comment.pull_request
    raise UnprocessableError if pull_request.nil?

    begin
      suggested_change = DiffEntrySuggestedChange.new(
        repository: T.must(repository),
        pull_request:,
        diff_entries: suggestion&.diff_entries
      )

      default_commit_message = "Potential fix for code quality finding '#{title}'"
      co_author_note = "Co-authored-by: Copilot Autofix powered by AI <#{pr_review_comment.user&.git_author_email}>"

      suggested_change.commit_change_for_user(
        author: user,
        current_oid: pull_request.head_sha,
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

    evaluator&.apply_suggestion(comment: self, user:, pull: pull_request)
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
    #DV: we probably want to allow each service to define their choices in the evaluator
    raise ArgumentError, "invalid feedback choice" unless choices.all? { |choice| CodeScanning::Autofix::FEEDBACK_OPTIONS.include?(choice) }

    # DV: Add a common event for all the automated review comments
    evaluator&.feedback(comment: self, user:, feedback:, choices:, text_response:)
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
