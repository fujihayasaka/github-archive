# typed: strict
# frozen_string_literal: true

class Businesses::CopilotLicensingOrganizationAssignmentController < Businesses::BusinessController

  before_action :dotcom_required
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :ensure_enterprise_copilot_licensing_enabled

  javascript_bundle :copilot

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    only: [:index]

  sig { void }
  def index
    query = params[:query].presence
    organizations_matching_query = this_business.filtered_organizations(
      viewer: current_user,
      query: query
    )

    query_with_access = params[:withAccess] == "true"

    orgs_with_copilot_access = []
    orgs_without_copilot_access = []

    organizations_matching_query.each do |organization|
      copilot_organization = Copilot::Organization.new(organization)
      copilot_plan = copilot_organization.copilot_plan.present? && copilot_organization.copilot_enabled? ? copilot_organization.copilot_plan : "disabled"
      copilot_can_be_reenabled = copilot_plan == "disabled" && Copilot::SeatAssignment.for_organization(organization).any?
      previous_plan = copilot_can_be_reenabled ? copilot_organization.copilot_plan : nil

      # We're only going to be quering for either organizations that have access or don't have access. There's no point in populating both lists.
      org_has_access = copilot_plan != "disabled"
      next if query_with_access && !org_has_access
      next if !query_with_access && org_has_access

      license_count = Copilot::Seat.for_organization(organization).count
      expiration_date = copilot_organization.pending_plan_downgrade_date&.strftime("%Y-%m-%d")
      org_url = user_path(organization)
      avatar_url = organization.primary_avatar_url

      org = {
        login: organization.display_login,
        id: organization.id,
        licenseCount: license_count,
        copilotPlan: copilot_plan,
        copilotCanBeReenabled: copilot_can_be_reenabled,
        expirationDate: expiration_date,
        orgUrl: org_url,
        avatarUrl: avatar_url,
        newPlan: copilot_plan,
        previousPlan: previous_plan,
      }

      if org_has_access
        orgs_with_copilot_access << org
      else
        orgs_without_copilot_access << org
      end
    end

    render json: {
      withCopilotAccess: orgs_with_copilot_access,
      withoutCopilotAccess: orgs_without_copilot_access,
    }
  end

  private

  sig { returns(Copilot::Business) }
  memoize def copilot_business
    ::Copilot::Business.new(this_business)
  end
end
