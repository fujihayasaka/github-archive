# typed: true
# frozen_string_literal: true

class Orgs::CopilotSettings::TeamSeatsController < Orgs::Controller
  include ApplicationController::VerifiedFetchDependency
  include Orgs::CopilotSettings::SeatManagementDependency

  before_action :dotcom_required
  before_action :org_admins_only
  before_action :check_not_legacy_plan
  before_action :check_copilot_available

  allow_verified_fetch only: [:destroy]

  sig { void }
  def create
    team = Team.find_by(name: params[:team], organization: this_organization)
    if team
      result = copilot_organization.assign([team], current_user)
      if result.error
        error = result.error
      end
    else
      error = "Team not found"
    end

    render_index_json
  end

  sig { void }
  def destroy
    team = Team.find(params[:team_id])
    copilot_organization.unassign([team], current_user)

    render_index_json
  end
end
