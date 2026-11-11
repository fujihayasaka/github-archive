# typed: strict
# frozen_string_literal: true

class Repos::SecurityAndAnalysis::AutomatedReviewCommentsController < AbstractRepositoryController
  include GitHub::RateLimitedRequest
  include JsonDependency
  include VerifiedFetchDependency

  allow_verified_fetch

  before_action :login_required
  before_action :require_xhr, only: [:dismiss, :reopen, :feedback]
  before_action :parse_json_params
  before_action :writable_repository_required, except: %i(feedback)
  before_action :content_authorization_required, only: [:apply_suggestion]
  around_action :set_log_context

  sig { void }
  def dismiss  # rubocop:todo GitHub/UseRestfulActions
    comment = load_comment
    return head :not_found unless comment

    reason = params[:reason]
    return head :bad_request if reason.nil?

    resolution_note = GitHub::Turboscan.normalize_dismissed_comment(params[:resolution_note])
    return head :bad_request if resolution_note && resolution_note.length > AutomatedReviewComment::RESOLUTION_NOTE_MAX_LENGTH
    return head :bad_request if resolution_note.blank? && comment.delegated_dismissal_enabled?

    begin
      if comment.delegated_dismissal_enabled?
        comment.request_dismissal(user: current_user, reason: reason, resolution_note: resolution_note)
      else
        comment.dismiss!(user: current_user, reason: reason, resolution_note: resolution_note)
      end
    rescue AutomatedReviewComment::UnprocessableError
      return render json: { error: "Unable to dismiss the comment." }, status: :unprocessable_entity
    rescue AutomatedReviewComment::PermissionError
      return render json: { error: "User is not authorized to dismiss comments." }, status: :forbidden
    rescue AutomatedReviewComment::ArgumentError => e
      return render status: :bad_request, json: { error: e.message }
    end

    render json: { message: "Automated review comment was successfully dismissed." }, status: :ok
  end

  sig { void }
  def reopen  # rubocop:todo GitHub/UseRestfulActions
    comment = load_comment
    return head :not_found unless comment

    begin
      comment.reopen!(user: current_user)
    rescue AutomatedReviewComment::UnprocessableError
      return render json: { error: "Unable to reopen the comment." }, status: :unprocessable_entity
    rescue AutomatedReviewComment::PermissionError
      return render json: { error: "User is not authorized to reopen comments." }, status: :forbidden
    end

    render json: { message: "Automated review comment was successfully reopened." }, status: :ok
  end

  sig { void }
  def apply_suggestion  # rubocop:todo GitHub/UseRestfulActions
    comment = load_comment
    return render status: :not_found, json: { error: "Automated review comment not found" } unless comment

    log_context = {
      "gh.pull_request.id": comment.pull_request_id,
      "gh.automated_review_comment.id": comment.id,
    }
    GitHub.logger.info("Applying automated suggestion", **log_context)

    start = Time.now
    begin
      comment.apply_suggestion!(user: current_user, commit_message: params[:message].to_s)
    rescue AutomatedReviewComment::InvalidDataError => e
      GitHub.dogstats.distribution_timing_since("pull_request.suggestions.apply_single.duration", start, tags: ["outcome:error_invalid_data"])
      Failbot.report(e, log_context)
      return render status: :unprocessable_entity, json: { error: "Unable to apply suggestion." }
    rescue AutomatedReviewComment::ConflictError => e
      GitHub.dogstats.distribution_timing_since("pull_request.suggestions.apply_single.duration", start, tags: ["outcome:error_conflict"])
      Failbot.report(e, log_context)
      return render status: :unprocessable_entity, json: { error: e.message.presence || "Unable to apply suggestion." }
    rescue AutomatedReviewComment::UnprocessableError => e
      GitHub.dogstats.distribution_timing_since("pull_request.suggestions.apply_single.duration", start, tags: ["outcome:error_unprocessable"])
      return render status: :unprocessable_entity, json: { error: e.message.presence || "Unable to apply suggestion." }
    rescue AutomatedReviewComment::PermissionError => e
      GitHub.dogstats.distribution_timing_since("pull_request.suggestions.apply_single.duration", start, tags: ["outcome:unauthorized"])
      return render status: :unauthorized, json: { error: "User is not authorized to apply suggestions." }
    end

    GitHub.dogstats.distribution_timing_since("pull_request.suggestions.apply_single.duration", start, tags: ["outcome:success"])
    GitHub.logger.info("Automated suggestion applied successfully", **log_context)
    render json: { message: "Suggestion was successfully applied." }, status: :ok
  end

  sig { void }
  def feedback  # rubocop:todo GitHub/UseRestfulActions
    comment = load_comment
    return render status: :not_found, json: { error: "Automated review comment not found" } unless comment

    return render status: :bad_request, json: { error: "feedback must be present" } unless params[:feedback].present?
    feedback = params[:feedback].to_sym

    choices = Array(params[:feedback_choice]).map { |choice| choice.to_sym }

    text_response = params[:text_response]
    if text_response.present? && !params[:text_response].is_a?(String)
      return render status: :bad_request, json: { error: "text_response must be a String" }
    end

    begin
      comment.feedback!(user: current_user, feedback:, choices:, text_response:)
    rescue AutomatedReviewComment::ArgumentError => e
      return render status: :bad_request, json: { error: e.message }
    end

    render json: { message: "Feedback was successfully processed." }, status: :ok
  end

  private

  sig { returns(T.nilable(AutomatedReviewComment)) }
  def load_comment
    AutomatedReviewComment.find_by(id: params[:id], repository: current_repository)
  end

  sig { returns(T.untyped) }
  def content_authorization_required
    authorize_content(:pull_request, action_to_authorize: :apply_suggestions, repo: current_repository)
  end

  sig { params(block: T.proc.void).void }
  def set_log_context(&block)
    context = {
      "gh.request.controller": controller_name,
      "gh.request.action": action_name,
      "gh.user.id": current_user.id,
      "gh.repository.id": current_repository.id,
    }
    Failbot.push(context)
    GitHub.logger.with_named_tags(**context) { yield }
  end

end
