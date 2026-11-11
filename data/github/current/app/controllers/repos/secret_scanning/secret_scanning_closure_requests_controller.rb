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
    status = params.require(:status)&.strip&.downcase

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

    # subsequent statuses (besides "cancel") require user to have "view alerts" permission
    return render json: { error: "User does not have permission to view secret scanning alerts" }, status: :forbidden unless token_scanning.view_alerts_allowed?(current_user)

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

    message = params[:message]&.strip
    is_success_msg, reason_msg = ::SecretScanning::Services::DelegatedAlertClosuresService.validate_request_message(message)
    if !is_success_msg
      flash[:error] = reason_msg
      return render json: { error: reason_msg }, status: :unprocessable_entity
    end

    is_success_review, reason_review = ::SecretScanning::Services::DelegatedAlertClosuresService.new.review_exemption_request!(
      exemption_request:,
      status:,
      message:,
      user:,
      repo: current_repository,
    )
    unless is_success_review
      code = reason_review.present? && reason_review.include?("Failed to close alert") ? :internal_server_error : :unprocessable_entity
      return render json: { error: reason_review }, status: code
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

  sig { void }
  def check_delegated_alert_closures_enabled
    render_404 unless delegated_closures.enabled?
  end

  sig { void }
  def check_user_has_view_permission
    # short circuit if the user can view alerts for the current repository
    return if token_scanning.view_alerts_allowed?(current_user)
    # other times when the user cannot view alerts for the current repo, such as outside collaborators
    # we check if the user has access to the repository (outside collaborators do)
    return if ::SecretScanning::AccessControl::CommitAuthorView.new(current_repository).has_access_to_repository?(current_user)

    render json: { error: "User does not have permission to view secret scanning alerts" }, status: :forbidden
  end

  sig { void }
  def check_user_has_review_permission
    render json: { error: "User does not have permission to review secret scanning alert closure requests" }, status: :forbidden unless current_repository.organization&.has_review_delegated_alert_closure_fgp?(current_user)
  end
end
