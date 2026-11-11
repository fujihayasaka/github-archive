# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# Removes granular permissions for a removed org member from the orgs Projects vNext
class BulkRemoveOrgMemberProjectsNextAccessJob < ApplicationJob
  queue_as :bulk_remove_org_member_projects_next_access

  retry_on_dirty_exit

  # Batch size of 5000 balances MySQL IN clause performance with round-trip overhead
  # For 400k projects: 80 batches vs 400 batches at size 1000
  BATCH_SIZE = 5000

  resolve_tenant_context do |org, _user|
    org&.resolve_tenant
  end

  def perform(org, user_ids)
    all_memex_ids = with_read do
      UserRole.where(actor_id: user_ids, target_type: "MemexProject").pluck(:target_id).uniq
    end

    return if all_memex_ids.empty?

    # Filter to only this org's projects, batching for large arrays to avoid MySQL limits
    org_memex_ids = []
    with_read do
      all_memex_ids.in_groups_of(BATCH_SIZE, false) do |batch|
        org_memex_ids.concat(MemexProject.where(id: batch, owner_id: org.id).pluck(:id))
      end
    end

    return if org_memex_ids.empty?

    role_ids = with_read { Role.system_project_roles.pluck(:id) }

    # Use delete_all instead of destroy_all to avoid loading MemexProject associations
    # and triggering N+1 repository queries
    # Batch deletion for large arrays to avoid MySQL limits
    with_write do
      org_memex_ids.in_groups_of(BATCH_SIZE, false) do |batch|
        GH::DualWriter.track do
          UserRole.where(
            role_id: role_ids,
            actor_type: User.to_s,
            actor_id: user_ids,
            target_type: MemexProject.to_s,
            target_id: batch
          ).delete_all
        end
      end
    end

    # Manually clear permissions cache since we skipped destroy callbacks
    PermissionCache.clear

    GitHub.dogstats.increment("org.memexes.user_access_removed", tags: ["implementation:batched"])
  end
end
