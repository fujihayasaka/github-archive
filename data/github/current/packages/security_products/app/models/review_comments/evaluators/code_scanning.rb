# typed: strict
# frozen_string_literal: true

class ReviewComments::Evaluators::CodeScanning < ReviewComments::AutomatedReviewCommentEvaluator
  # Note(@aliceclv): we currently use code_scanning namespace for code quality
  # We should consider moving to code_quality
  FEEDBACK_OPTIONS = T.let({
    CODE_SCANNING_AUTOFIX_FEEDBACK_ALERT_NOT_RELEVANT: "The alert is not relevant, and no fix is needed",
    CODE_SCANNING_AUTOFIX_FEEDBACK_FIX_HAS_ERRORS: "The fix is partially correct, but has errors",
    CODE_SCANNING_AUTOFIX_FEEDBACK_FIX_IS_UNHELPFUL: "The fix is not helpful at all",
    CODE_SCANNING_AUTOFIX_FEEDBACK_FIX_WONT_ADDRESS_PROBLEM: "Unsure if this fix will address the security vulnerability",
    CODE_SCANNING_AUTOFIX_FEEDBACK_FIX_WILL_BREAK_FUNCTIONALITY: "Unsure if this fix will break code functionality",
    CODE_SCANNING_AUTOFIX_FEEDBACK_OTHER: "Other reason"
  }, T::Hash[Symbol, String])

  DISMISSAL_OPTIONS = T.let([
    { value: "FALSE_POSITIVE", label: "False positive", description: "This code is not valid" },
    { value: "USED_IN_TESTS", label: "Used in tests", description: "This code is not used in production" },
    { value: "WONT_FIX", label: "Won't fix", description: "This code is not relevant" },
  ], T::Array[{ value: String, label: String, description: String }])

  sig { override.returns(T::Boolean) }
  def dismissable?
    true
  end

  sig { override.returns(T::Boolean) }
  def delegated_dismissal_enabled?
    CodeScanning::AlertDismissalService.new(@repository).delegated_dismissal_enabled?
  end

  sig { override.params(user: User, comment: T.nilable(AutomatedReviewComment)).returns(T::Boolean) }
  def can_dismiss?(user:, comment: nil)
    @repository.code_scanning_writable_by?(user)
  end

  sig do
    override.params(
      comment: AutomatedReviewComment,
      user: User,
      reason: String,
      resolution_note: T.nilable(String)
    ).void
  end
  def dismiss(comment:, user:, reason:, resolution_note:)
    code_scanning_reason = GitHub::Turboscan.to_resolution(reason)
    raise AutomatedReviewComment::ArgumentError, "Invalid reason: #{reason}" if code_scanning_reason.nil?

    CodeScanning::AlertDismissalService::close_alerts(
      repository: @repository,
      alert_numbers: [comment.resource_id.to_i],
      resolution: code_scanning_reason,
      resolver: user,
      resolution_note: resolution_note,
    ).first
  end

  sig do
    override.params(
      comment: AutomatedReviewComment,
      user: User,
      reason: String,
      resolution_note: T.nilable(String)
    ).void
  end
  def request_dismissal(comment:, user:, reason:, resolution_note:)
    code_scanning_reason = GitHub::Turboscan.to_resolution(reason)
    raise AutomatedReviewComment::ArgumentError, "Invalid reason: #{reason}" if code_scanning_reason.nil?

    begin
      CodeScanning::AlertDismissalService.request_dismissal(
        repository: @repository,
        requester: user,
        alert_number: comment.resource_id.to_i,
        resolution: code_scanning_reason,
        resolution_note: resolution_note,
        pr_review_thread_id: nil,
        campaign_id: nil,
      )
    rescue CodeScanning::AlertDismissalService::PendingRequestExistsError
      # Treat an existing pending dismissal request as a no-op/success.
      nil
    rescue CodeScanning::AlertDismissalService::AlertDismissalError => e
      raise AutomatedReviewComment::UnprocessableError, e.message
    end
  end

  sig { override.params(user: User).returns(T::Boolean) }
  def can_reopen?(user:)
    @repository.code_scanning_writable_by?(user)
  end

  sig do
    override.params(
      comment: AutomatedReviewComment,
      user: User,
    ).void
  end
  def reopen(comment:, user:)
    CodeScanning::AlertDismissalService::open_alert(
      repository: @repository,
      alert_number: comment.resource_id.to_i,
      refresh_reason: :ui_alert_update,
      resolver: user,
    )
  end

  sig do
    override.params(
      comment: AutomatedReviewComment,
      user: User,
      pull: PullRequest,
    ).void
  end
  def apply_suggestion(comment:, user:, pull:)
    response = GitHub::Turboscan::SuggestedFixes.apply_suggested_fix(
      repository_id: @repository.id,
      alert_number: comment.resource_id.to_i,
      ref_names_bytes: pull.build_ref_names_bytes_for_code_scanning_suggested_fix,
      actor_id: user.id,
      pull_request_id: pull.id,
    )

    GlobalInstrumenter.instrument("code_scanning.autofix_event", {
      repository_id: @repository.id,
      alert_number: comment.resource_id.to_i,
      event_type: :AUTOFIX_EVENT_TYPE_COMMITTED,
      pull_request_id: pull.id,
      pull_request_number: pull.number,
    })
  end

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
    payload = {
      repository_id: @repository.id,
      user_analytics_tracking_id: user.analytics_tracking_id,
      pull_request_id: comment.pull_request&.id,
      pull_request_number: comment.pull_request&.number,
      alert_number: comment.resource_id,
      type: feedback,
      choice: choices,
      text_response: text_response,
    }

    GlobalInstrumenter.instrument("code_scanning.autofix_feedback", payload)
  end

  sig { override.returns(T::Array[{ value: String, label: String }]) }
  def feedback_options
    FEEDBACK_OPTIONS.map do |value, label|
      { value: value.to_s, label: label }
    end
  end

  sig { override.returns(T::Array[{ value: String, label: String, description: String }]) }
  def dismissal_options
    DISMISSAL_OPTIONS
  end

  sig do
    override.params(
      comment: AutomatedReviewComment
    ).returns(T.nilable(ReviewComments::DelegatedDismissalRequest))
  end
  def current_delegated_dismissal_request(comment:)
    request = CodeScanning::AlertDismissalService.find_request_by_alert_number(repository:, alert_number: comment.resource_id.to_i)
    return nil if request.nil?

    requester = T.must(request.requester)
    reason = current_delegated_dismissal_request_reason(request:)
    status = ReviewComments::DelegatedDismissalRequest::RequestStatus.from_exemptions_evaluation_result(request.compute_status)
    reviewer = request.latest_response&.reviewer

    ReviewComments::DelegatedDismissalRequest.new(
      requester:,
      reason:,
      status:,
      reviewer:
    )
  end

  sig do
    params(
      request: Exemptions::ExemptionRequest,
    ).returns(T.nilable(String))
  end
  def current_delegated_dismissal_request_reason(request:)
    resolution = request.metadata["resolution"]&.to_i
    return nil if resolution.nil?

    resolution = Turboscan::Proto::ResultResolution.lookup(resolution)
    return nil if resolution.nil?

    GitHub::Turboscan::CLOSED_REASONS[resolution]
  end
end
