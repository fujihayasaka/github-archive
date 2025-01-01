# typed: true
# frozen_string_literal: true

class Repos::SecurityAndAnalysis::CodeScanning::AlertDismissalController < AbstractRepositoryController
  include ApplicationController::VerifiedFetchDependency

  before_action :login_required
  before_action :writable_repository_required
  before_action :has_protected_alert_dismissal?
  before_action :can_request_dismissal?, only: %i(create)

  allow_verified_fetch only: [:create]

  PAGE_SIZE = 25

  def create
    alert_numbers = Array(params[:number]).take(PAGE_SIZE).map(&:to_i).uniq
    return head :bad_request if alert_numbers.empty?

    resolution = GitHub::Turboscan.to_resolution(params[:reason])
    return head :bad_request if resolution.nil?

    resolution_note = GitHub::Turboscan.normalize_dismissed_comment(params[:resolution_note])
    return head :bad_request if !GitHub::Turboscan.dismissed_request_comment_valid?(resolution_note)

    # if this request comes from a PR page it should include the id of the alert's review thread
    # so we can resolve it
    pr_review_thread_id = params[:pull_request_review_thread]
    alert_numbers.each do |alert_number|
      begin
        CodeScanning::AlertDismissalService.request_dismissal(
          repository: current_repository,
          requester: current_user,
          alert_number: alert_number,
          resolution: resolution,
          resolution_note: resolution_note,
          pr_review_thread_id: pr_review_thread_id,
          campaign_id: nil,
        )
      rescue CodeScanning::AlertDismissalService::PendingRequestExistsError
        next
      rescue CodeScanning::AlertDismissalService::AlertDismissalError
        flash[:error] = "There was an issue creating the request. Please try again."
        break
      end
    end

    redirect_to :back
  end

  def review_request # rubocop:todo GitHub/UseRestfulActions
    return head :bad_request if params[:request_id].nil?
    return head :bad_request if params[:action_type].nil?

    request_id = params[:request_id].to_i
    action_type = params[:action_type]

    # Validate action_type
    return head :bad_request unless %w[approve reject].include?(action_type)

    dismissal_request = CodeScanning::AlertDismissalService.find_request_by_id(repository: current_repository, request_id:)
    return render_404 unless dismissal_request
    return render_404 unless CodeScanning::AlertDismissalService.can_review_dismissal_request?(request: dismissal_request, user: current_user)


    begin
      CodeScanning::AlertDismissalService.review_dismissal_request!(
        dismissal_request:,
        status: action_type,
        message: params[:comment] || "",
        user: current_user,
        repo: current_repository
      )
    rescue CodeScanning::AlertDismissalService::AlertDismissalError
      flash[:error] = "There was an issue #{action_type == 'approve' ? 'approving' : 'rejecting'} the request. Please try again."
    end
    redirect_to :back
  end

  private

  def has_protected_alert_dismissal?
    render_404 unless CodeScanning::AlertDismissalService.new(current_repository).delegated_dismissal_enabled?
  end

  def can_request_dismissal?
    render_404 unless current_repository.code_scanning_writable_by?(current_user)
  end
end
