# typed: strict
# frozen_string_literal: true

class ClearOrganizationRoleAssignmentsJob < ApplicationJob
  queue_as :clear_role_assignments

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  sig { params(org_id: Integer, business_id: T.nilable(Integer)).void }
  def perform(org_id, business_id: nil)
    GitHub.logger.info(
      "info.message" => "Starting ClearOrganizationRoleAssignmentsJob",
      "gh.organization.id" => org_id,
      "gh.business.id" => business_id,
    )

    clear_business_level_role_assignments(org_id, business_id)
  end

  private

  sig { params(org_id: Integer, business_id: T.nilable(Integer)).void }
  def clear_business_level_role_assignments(org_id, business_id)
    return if business_id.nil?

    user_roles_targeting_org = UserRole
    .where(target_id: business_id, target_type: "Business")
    .where("JSON_CONTAINS(conditions_target_ids, ?)", org_id)

    user_roles_targeting_org.each do |user_role|
      user_role = T.cast(user_role, UserRole)
      new_target_ids = user_role.conditions_target_ids.reject { |id| id == org_id }

      begin
        with_write do
          if new_target_ids.empty?
            user_role.destroy!
          else
            user_role.update!(conditions: UserRoleCondition.new(
              target: UserRoleCondition::Target::SomeOrgs,
              target_ids: new_target_ids,
            ))
          end
        end
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed => e
        Failbot.report(e)
        next
      end
    end
  end
end
