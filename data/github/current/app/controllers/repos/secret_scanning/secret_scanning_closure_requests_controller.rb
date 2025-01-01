# typed: strict
# frozen_string_literal: true

class Repos::SecretScanning::SecretScanningClosureRequestsController < AbstractRepositoryController
  include ApplicationController::VerifiedFetchDependency
  include SecretScanning::ExemptionConstants
  include ApplicationController::JsonDependency

  allow_verified_fetch only: [:update]

  # Before actions

  before_action :login_required
  before_action :check_delegated_alert_closures_enabled
  before_action :check_user_has_view_permission
  before_action :parse_json_params, only: [:update]

  sig { void }
  def update
    number = params.require(:number)
    message = params.require(:message)
    status = params.require(:status)&.strip&.downcase
    body = request&.body

    if message.length > 280
      flash[:error] = "Comment is too long (maximum is 280 characters)"
      return render json: { error: "Comment is too long (maximum is 280 characters)" }, status: :unprocessable_entity
    end

    return render_404 unless (user = current_user)

    exemption_request = Exemptions::ExemptionRequest.where(request_type: CLOSURE_EXEMPTION_REQUEST_TYPE, repository: current_repository, number:).first
    return render_404 unless exemption_request
    return render json: { error: "Request has expired" }, status: :forbidden if exemption_request.expired?

    is_valid_reviewer = exemption_request.is_valid_reviewer?(user)

    if status == "cancel"
      # Only bypass reviewers and the requesting user can cancel the request
      return render json: { error: "Only the requester and reviewers can cancel requests" }, status: :forbidden unless is_valid_reviewer || exemption_request.requester == current_user

      # A request can only be cancelled if it hasn't yet been completed.
      if exemption_request.status.to_sym != :completed
        exemption_request.status = :cancelled
        exemption_request.save!

        GitHub.instrument("secret_scanning_closure_request.cancel", {
          actor: current_user,
          repo: current_repository,
          org: current_repository.organization,
          number: exemption_request.number,
          alert_number: exemption_request.resource_identifier,
        })
      end
      # Regardless, redirect back to show. This will refresh the page's state and show the cancellation (and/or any other new events).
      return render json: { success: true }, status: 201
    end

    if status == "dismiss"
      return render json: { error: "Only reviewers can dismiss a response" }, status: :forbidden unless is_valid_reviewer
      response_id = params.require(:responseId)
      exemption_response = Exemptions::ExemptionResponse.where(id: response_id, reviewer_id: current_user.id).first
      return render_404 unless exemption_response
      exemption_response.status = :dismissed
      exemption_response.save!
      return render json: { success: true }, status: 201
    end

    # Only delegated admins can approve/reject the exemption request (approve/reject)
    # Admins can't approve own request
    return render json: { error: "Actor is not a valid reviewer" }, status: :forbidden unless is_valid_reviewer

    if status == "approve"
      # TODO: remove this and move to post_approval_action once that work is complete
      alert_number = exemption_request.resource_identifier.to_i
      return render json: { error: "Invalid alert number - must be > 0" }, status: :bad_request unless alert_number > 0

      reason = exemption_request.metadata["reason"]

      if !is_valid_reason?(reason)
        return render json: { error: "Invalid resolution: #{reason}" }, status: :bad_request
      end

      close_error = alerts_service.resolve_alert(repository: current_repository, user: current_user, numbers: [alert_number], resolution: reason)

      if close_error != nil
        return render json: { error: "Failed to close alert: #{close_error}" }, status: :internal_server_error
      end

      response_body = Exemptions::ExemptionResponse.approve!(exemption_request, user, message: message)
      exemption_request.approved!

      GitHub.instrument("secret_scanning_closure_request.approve", {
        actor: current_user,
        repo: current_repository,
        org: current_repository.organization,
        number: exemption_request.number,
        alert_number: exemption_request.resource_identifier,
        request_reviewer_comment: message,
      })

    elsif status == "reject"
      response_body = Exemptions::ExemptionResponse.reject!(exemption_request, user, message: message)
      GitHub.instrument("secret_scanning_closure_request.deny", {
        actor: current_user,
        repo: current_repository,
        org: current_repository.organization,
        number: exemption_request.number,
        alert_number: exemption_request.resource_identifier,
        request_reviewer_comment: message,
      })
    end
    render(
      json: { success: true },
      status: 201,
    )
  end

  private

  sig { returns(SecretScanning::Features::Repo::TokenScanning) }
  memoize def token_scanning
    SecretScanning::Features::Repo::TokenScanning.new(current_repository)
  end

  sig { returns(SecretScanning::Features::Repo::DelegatedClosures) }
  memoize def delegated_closures
    SecretScanning::Features::Repo::DelegatedClosures.new(current_repository)
  end

  sig { returns(SecretScanning::Services::AlertsService) }
  memoize def alerts_service
    SecretScanning::Services::AlertsService.new
  end

  sig { void }
  def check_delegated_alert_closures_enabled
    render_404 unless delegated_closures.enabled?
  end

  sig { void }
  def check_user_has_view_permission
    render json: { error: "User does not have permission to view secret scanning alerts" }, status: :forbidden unless token_scanning.view_alerts_allowed?(current_user)
  end

  sig { void }
  def check_user_has_review_permission
    render json: { error: "User does not have permission to review secret scanning alert closure requests" }, status: :forbidden unless current_repository.organization&.has_review_delegated_alert_closure_fgp?(current_user)
  end

  sig { params(reason: String).returns(T::Boolean) }
  def is_valid_reason?(reason)
    reason.present? && reason.in?(SecretScanning::ExemptionConstants::VALID_REASONS)
  end
end
