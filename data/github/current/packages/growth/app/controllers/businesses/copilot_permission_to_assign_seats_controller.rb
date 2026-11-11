# typed: strict
# frozen_string_literal: true

# This controller is responsible for enabling Copilot for a business to assign seats to an organization.
# It changes the Business to enable Copilot for the organization to `Enabled for Selected Members`
# This controller is used on the `Allow organization to assign Copilot seats` CTA.
class Businesses::CopilotPermissionToAssignSeatsController < Businesses::BusinessController
  include ApplicationController::VerifiedFetchDependency

  before_action :dotcom_required
  before_action :login_required
  before_action :non_emu_required
  before_action :business_owner_required
  before_action :organization_admin_required
  before_action :business_not_downgraded_to_free_plan_required

  allow_verified_fetch only: [:update]

  sig { void }
  def update
    copilot_business.enable_copilot_for_selected_organizations!([organization.id], current_user) unless copilot_business.copilot_enabled_for_all_organizations?
    if copilot_organization.seat_management_disabled?
      copilot_organization.seat_management_selected_teams_and_users!(keep_assignments: true)
      analytics_event(
        category: "copilot_permission_to_assign_seats",
        action: "enabled_org",
        label: "user:#{current_user.id};org:#{organization.id}",
      )
    end

    respond_to do |format|
      format.json do
        payload = Copilot::Organizations::SeatManagement::Payload.new(organization: organization, params: params, current_user: current_user).call
        render json: { payload:  payload }
      end
      format.html { redirect_to settings_org_copilot_seat_management_path(organization), notice: "#{organization.display_login} have been enabled to assign Copilot seats." }
    end

  end

  private

  sig { returns(Copilot::Business) }
  memoize def copilot_business
    Copilot::Business.new(this_business)
  end

  sig { returns(Copilot::Organization) }
  memoize def copilot_organization
    Copilot::Organization.new(organization)
  end

  sig { returns(Organization) }
  memoize def organization
    this_business.organizations.find_by_login(params[:organization_id])
  end

  sig { void }
  def organization_admin_required
    render_404 unless organization.adminable_by?(current_user)
  end
end
