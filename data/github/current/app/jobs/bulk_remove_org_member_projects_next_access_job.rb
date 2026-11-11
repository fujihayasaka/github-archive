# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# Removes granular permissions for a removed org member from the orgs Projects vNext
class BulkRemoveOrgMemberProjectsNextAccessJob < ApplicationJob
  queue_as :bulk_remove_org_member_projects_next_access

  retry_on_dirty_exit

  BATCH_SIZE = 100

  resolve_tenant_context do |org, _user|
    org&.resolve_tenant
  end

  def perform(org, user_ids)
    offset = 0

    memex_ids = UserRole.where(actor_id: user_ids, target_type: "MemexProject").pluck(:target_id).uniq

    loop do
      memex_ids = MemexProject.where(
        id: memex_ids,
        owner_id: org.id
      )
      .order(:id)
      .limit(BATCH_SIZE)
      .offset(offset)
      .pluck(:id)

      memex_roles = Role.system_project_roles

      memex_roles.each do |role|
        with_write do
          Permissions::Granters::RoleGranter.bulk_revoke(
              actor_ids: user_ids,
              actor_type: User.to_s,
              target_ids: memex_ids,
              target_type: MemexProject.to_s,
              role: role
            )
        end
      end

      GitHub.dogstats.increment("org.memexes.user_access_removed")

      # we're done if this was the last or only batch
      break if memex_ids.count < BATCH_SIZE

      offset += memex_ids.count - 1
    end
  end
end
