# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# Removes enterprise-owned organization role assignments from an organization
class RemoveBusinessOrgRoleAssignmentsJob < ApplicationJob
  queue_as :remove_business_org_role_assignments

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  sig { params(business_id: Integer, organization_id: Integer).void }
  def perform(business_id, organization_id)
    GitHub.logger.info(
      "info.message" => "Starting RemoveBusinessOrgRoleAssignmentsJob",
      "gh.organization.id" => organization_id,
      "gh.business.id" => business_id,
    )

    deleted = with_write do
      enterprise_org_role_ids = OrganizationRole.where(owner_type: "Business", owner_id: business_id).pluck(:id)
      next [] if enterprise_org_role_ids.empty? # set deleted to empty array if there are no roles

      AppSecurity.domain.user_roles.destroy_by_conditions(
        target_type: "Organization",
        role_id: enterprise_org_role_ids,
        target_id: organization_id
      )
    end

    GitHub.logger.info(
      "info.message" => "Finished RemoveBusinessOrgRoleAssignmentsJob",
      "gh.organization.id" => organization_id,
      "gh.business.id" => business_id,
      "gh.deleted_assignments_count" => deleted.size,
    )
  end
end
