# typed: true
# frozen_string_literal: true

class Repos::CodeScanning::AlertTrackingLinksController < AbstractRepositoryController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include CodeScanning::ControllerAccessChecks

  allow_verified_fetch only: [:update]

  before_action :check_code_scanning_write
  before_action :parse_json_params, only: [:update]

  ABSENT_ISSUE_ID = 0

  def update
    alert_number = params[:number].to_i
    repository_id = current_repository.id

    unless AlertTrackingLinks.enabled?(current_repository)
      return render status: 404, json: { message: "Cannot create alert tracking links" }
    end

    issue_id = if params[:issue_id].nil?
      ABSENT_ISSUE_ID
    else
      begin
        Integer(params[:issue_id])
      rescue ArgumentError, TypeError
        return render status: 422, json: { message: "Invalid issue id" }
      end
    end

    if issue_id != ABSENT_ISSUE_ID
      issue = Issue.find_by(id: issue_id)
      # Return 404 when issue is not readable by user to prevent users checking for issue existence
      if !issue || !issue.readable_by?(current_user)
        return render status: 404, json: { message: "Issue does not exist" }
      end
    end

    request = ::Turboscan::Proto::SetAlertTrackingLinksRequest.new(
      alert_number:,
      issue_id:,
      repository_id:,
      tracking_system: ::Turboscan::Proto::TrackingSystem::TRACKING_SYSTEM_GITHUB_ISSUE
    )

    response = GitHub::Turboscan.set_alert_tracking_links(request.to_h)
    if response.blank? || response.error.present?
      if response&.error&.code == :not_found
        return render status: 422, json: { message: "Could not find the alert" }
      end
      return render status: 500, json: { message: "Could not set the alert tracking link" }
    end

    render status: 200, json: {}
  end
end
