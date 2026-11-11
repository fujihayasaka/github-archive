# typed: true
# frozen_string_literal: true

class Orgs::CopilotSettings::InvitationsController < Orgs::Controller
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include Orgs::CopilotSettings::SeatManagementDependency

  allow_verified_fetch only: [:create, :destroy]

  before_action :dotcom_required
  before_action :org_admins_only
  before_action :check_not_legacy_plan
  before_action :check_copilot_available
  before_action :parse_json_params, only: [:create]

  sig { void }
  def create
    params[:invitation_ids] = [params[:invitation_id]]
    invitation_ids = params[:invitation_ids]
    if invitation_ids.present?
      invitations = OrganizationInvitation.where(id: invitation_ids)
      invitations.each do |invitation|
        invitation&.send_invitation_email
      end
    end
    render_index_json
  end

  sig { void }
  def destroy
    invitation = OrganizationInvitation.find(params[:invitation_id])
    unassign_invitations([invitation])
    render_index_json
  end
end
