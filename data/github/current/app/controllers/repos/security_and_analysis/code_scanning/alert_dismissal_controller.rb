# typed: true
# frozen_string_literal: true

class Repos::SecurityAndAnalysis::CodeScanning::AlertDismissalController < AbstractRepositoryController
  include ScanningControllerMethods
  include ApplicationController::VerifiedFetchDependency

  before_action :login_required
  before_action :writable_repository_required
  before_action :has_protected_alert_dismissal?
  before_action :can_request_dismissal?, only: %i(create)
  before_action :can_review_dismissal_request?, only: %i(approve_request reject_request)

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

  def approve_request # rubocop:todo GitHub/UseRestfulActions
    return head :bad_request if params[:request_id].nil?
    request_id = params[:request_id].to_i

    begin
      CodeScanning::AlertDismissalService.approve_request(
        repository: current_repository,
        reviewer: current_user,
        request_id: request_id,
      )
    rescue CodeScanning::AlertDismissalService::AlertDismissalError
      flash[:error] = "There was an issue approving the request. Please try again."
    end
    redirect_to :back
  end

  def reject_request # rubocop:todo GitHub/UseRestfulActions
    return head :bad_request if params[:request_id].nil?
    request_id = params[:request_id].to_i

    begin
      CodeScanning::AlertDismissalService.reject_request(
        repository: current_repository,
        reviewer: current_user,
        request_id: request_id,
      )
    rescue CodeScanning::AlertDismissalService::AlertDismissalError
      flash[:error] = "There was an issue rejecting the request. Please try again."
    end
    redirect_to :back
  end

  private

  def has_protected_alert_dismissal?
    render_404 unless CodeScanning::AlertDismissalService.new(current_repository).enabled?
  end

  def can_request_dismissal?
    render_404 unless current_repository.code_scanning_writable_by?(current_user)
  end

  def can_review_dismissal_request?
    render_404 unless CodeScanning::AlertDismissalService.is_valid_reviewer?(repository: current_repository, user: current_user)
  end
end
