# typed: true
# frozen_string_literal: true

class Repos::SecurityAndAnalysis::CodeScanning::AlertDismissalController < AbstractRepositoryController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  before_action :login_required
  before_action :writable_repository_required
  before_action :has_protected_alert_dismissal?, only: %i(create_request review_request)
  before_action :check_code_scanning_write?, only: %i(create_request close_alerts)
  before_action :try_parse_json_params, only: [:close_alerts, :create_request]

  allow_verified_fetch only: %i(create_request close_alerts)

  PAGE_SIZE = 25

  def create_request # rubocop:todo GitHub/UseRestfulActions
    alert_numbers = params[:number] || params[:alert_numbers]
    alert_numbers = Array(alert_numbers).take(PAGE_SIZE).map(&:to_i).uniq
    return head :bad_request if alert_numbers.empty?

    resolution = GitHub::Turboscan.to_resolution(params[:reason]) || GitHub::Turboscan.to_resolution(params[:resolution])
    return head :bad_request if resolution.nil?

    resolution_note = GitHub::Turboscan.normalize_dismissed_comment(params[:resolution_note])
    return head :bad_request if !GitHub::Turboscan.dismissed_request_comment_valid?(resolution_note)

    campaign_number = params[:campaign_number]&.to_i
    campaign_id = if campaign_number.present?
      SecurityCampaigns::SecurityCampaign.where(number: campaign_number, organization: current_repository.owner_id).pick(:id)
    end

    # if this request comes from a PR page it should include the id of the alert's review thread
    # so we can resolve it
    pr_review_thread_id = params[:pr_review_thread_id]
    alert_numbers.each do |alert_number|
      begin
        CodeScanning::AlertDismissalService.request_dismissal(
          repository: current_repository,
          requester: current_user,
          alert_number: alert_number,
          resolution: resolution,
          resolution_note: resolution_note,
          pr_review_thread_id: pr_review_thread_id,
          campaign_id: campaign_id,
        )
      rescue CodeScanning::AlertDismissalService::PendingRequestExistsError
        next
      rescue CodeScanning::AlertDismissalService::AlertDismissalError
        render json: { message: "There was an issue creating the request. Please try again." }, status: :unprocessable_entity
        return
      end
    end

    if campaign_id.present?
      analytics_event(
        category: "security_campaigns",
        action: "request_alert_dismissal",
        label: {
          "security_campaign_id": campaign_id,
          "resolution": params[:reason] || params[:resolution],
          "alert_numbers_count": alert_numbers.size
        }
      )
    end

    render json: { message: "Request submitted successfully" }
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

  def close_alerts # rubocop:todo GitHub/UseRestfulActions
    return render_404 if CodeScanning::AlertDismissalService.new(current_repository).delegated_dismissal_enabled?

    resolution = GitHub::Turboscan.to_resolution(params[:reason]) || GitHub::Turboscan.to_resolution(params[:resolution])
    return head :bad_request if resolution.nil?

    resolution_note = GitHub::Turboscan.normalize_dismissed_comment(params[:resolution_note])
    return head :bad_request if !GitHub::Turboscan.dismissed_comment_valid?(resolution_note)

    alert_numbers = params[:number] || params[:alert_numbers]
    alert_numbers = Array(alert_numbers).take(PAGE_SIZE).map(&:to_i).uniq
    return head :bad_request if alert_numbers.empty?

    begin
      CodeScanning::AlertDismissalService.close_alerts(
        repository: current_repository,
        alert_numbers: alert_numbers,
        resolution: resolution,
        resolver: current_user,
        resolution_note: resolution_note,
        pr_review_thread_id: params[:pr_review_thread_id]&.to_i,
      )
    rescue CodeScanning::AlertDismissalService::AlertNotFoundError
      render json: { message: "One or more alerts could not be found." }, status: :unprocessable_entity
      return
    rescue CodeScanning::AlertDismissalService::AlertDismissalError
      render json: { message: "There was an issue dismissing the alerts. Please try again." }, status: :unprocessable_entity
      return
    end

    campaign_number = params[:campaign_number]&.to_i
    campaign_id = if campaign_number.present?
      SecurityCampaigns::SecurityCampaign.where(number: campaign_number, organization: current_repository.owner_id).pick(:id)
    end
    if campaign_id.present?
      analytics_event(
        category: "security_campaigns",
        action: "close_alerts",
        label: {
          "security_campaign_id": campaign_id,
          "resolution": params[:reason] || params[:resolution],
          "alert_numbers_count": alert_numbers.size
        }
      )
    end

    render json: { message: "Alerts closed successfully" }
  end

  private

  def has_protected_alert_dismissal?
    render_404 unless CodeScanning::AlertDismissalService.new(current_repository).delegated_dismissal_enabled?
  end

  def check_code_scanning_write?
    render_404 unless current_repository.code_scanning_writable_by?(current_user)
  end
end
