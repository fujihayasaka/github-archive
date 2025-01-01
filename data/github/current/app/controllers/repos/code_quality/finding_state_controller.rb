# typed: strict
# frozen_string_literal: true

class Repos::CodeQuality::FindingStateController < Repos::CodeQuality::BaseRepositoryController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = T.let([
    "Orgs::SecurityCenter::SecurityCampaignsController#update",
  ].freeze, T::Array[String])

  before_action :check_code_quality_write
  before_action :try_parse_json_params

  allow_verified_fetch only: [:update]

  sig { void }
  def update
    finding_stable_id = params[:finding_stable_id]
    rule_id = params[:rule_id]
    file_path = params[:file_path]
    state = params[:state]

    return render status: 422, json: { message: "Rule ID is required" } if rule_id.blank?
    return render status: 422, json: { message: "File path is required" } if file_path.blank?
    return render status: 422, json: { message: "State is required" } if state.blank?

    dismissal_state = GitHub::Turboquality.to_dismissal_state(state)
    if dismissal_state.nil? || dismissal_state == Turboquality::Proto::DismissalState::DISMISSAL_STATE_UNKNOWN
      return render status: 422, json: { message: "Invalid state: #{state}" }
    end

    response = GitHub::Turboquality.client.update_dismissal(Turboquality::Proto::UpdateDismissalRequest.new(
      repository_id: current_repository.id,
      rule_id: rule_id,
      file_path: file_path,
      finding_stable_id: finding_stable_id,
      state: dismissal_state,
    ))
    raise StandardError.new(response.error.to_s) if response.error

    render status: 200, json: {}
  end
end
