# typed: true
# frozen_string_literal: true

# Removes granular permissions for a removed org member from the orgs Projects vNext
class RemoveOrgMemberProjectsNextAccessJob < ApplicationJob
  queue_as :remove_org_member_projects_next_access

  retry_on_dirty_exit

  BATCH_SIZE = 100

  resolve_tenant_context do |org, _user|
    org&.resolve_tenant
  end

  def perform(org, user)
    # Projects vNext is currently darkshipped to GHES. If the feature is not
    # enabled, return early. so that they do not stay enqueued
    return unless GitHub.projects_new_enabled?

    offset = 0

    memex_ids = UserRole.where(actor_id: user.id, target_type: "MemexProject").pluck(:target_id).uniq

    loop do
      memexes = MemexProject.where(
        id: memex_ids,
        owner_id: org.id
      )
      .order(:id)
      .limit(BATCH_SIZE)
      .offset(offset)

      memex_roles = Role.system_project_roles

      with_write do
        memexes.each do |memex|
          memex_roles.each do |role|
            Permissions::Granters::RoleGranter.new(
              actor: user, target: memex, role: role
            ).revoke_if_exists!
          end
        end
      end

      GitHub.dogstats.increment("org.memexes.user_access_removed")

      # we're done if this was the last or only batch
      break if memexes.count < BATCH_SIZE

      offset += memexes.count - 1
    end
  end
end
