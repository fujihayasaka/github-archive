# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# This job scans for externally managed EMU teams that have been orphaned where the team has been deleted
# but the subsequent cleanup jobs failed. These orphaned teams can prevent the team members from being deleted from an organization.
class ScanEmuOrganizationMembershipsJob < ApplicationJob
  queue_as :scan_emu_organization_memberships

  schedule interval: 24.hours, condition: -> { !GitHub.enterprise? }

  retry_on_dirty_exit
  retry_on(ActiveRecord::QueryCanceled, attempts: 2, wait: 5.minutes)

  exempt_from_tenant_context_requirement

  def perform
    # We only want to get OrganizationMembershipEntries where the org exists and the team does not.
    # DestroyTeamDependantsJob can only clean up OrganizationMembershipEntries with an org that exists.
    orphaned_team_memberships = get_orphaned_team_memberships

    if orphaned_team_memberships.empty?
      orphaned_org_memberships = []
    else
      orphaned_org_memberships = []
      orphaned_team_memberships.map(&:id).each_slice(1000) do |id_batch|
        if OrganizationMembershipEntry.break_joins_enabled?
          entries = OrganizationMembershipEntry.where(id: id_batch).to_a
          org_ids = entries.map(&:organization_id).uniq
          existing_org_ids = User.where(id: org_ids).pluck(:id).to_set
          orphaned_org_memberships.concat(
            entries.select { |e| existing_org_ids.include?(e.organization_id) }
          )
        else
          orphaned_org_memberships.concat(
            OrganizationMembershipEntry
              .joins("INNER JOIN users ON users.id = organization_membership_entries.organization_id")
              .where(id: id_batch)
              .to_a
          )
        end
      end

      orphaned_team_memberships = orphaned_team_memberships - orphaned_org_memberships

      # There are entries that do not have a team and an organization, so
      # just delete them.
      unless orphaned_team_memberships.empty?
        orphaned_team_memberships.split(100).each do |orphaned_team_memberships_batch|
          OrganizationMembershipEntry.where(id: orphaned_team_memberships_batch.map(&:id)).delete_all
        end
      end
    end

    if orphaned_org_memberships.empty?
      GitHub::Chatterbox.client.say!("#external-identities-ops", "No orphaned EMU Organization Membership Teams found today!") unless GitHub.enterprise?
      return
    end

    orphaned_teams = orphaned_org_memberships.inject({}) do |hash, ome|
      # The team at this point is already deleted so we have no info on the team,
      # but we need an empty hash for DestroyDependantsOperation.
      # adder_id is the team id
      team_info = [ome.adder_id.to_s, {}]
      if hash[ome.organization_id].present?
        hash[ome.organization_id][:team_ids_to_info].add(team_info)
        hash[ome.organization_id][:org_memberships_count] += 1
      else
        hash[ome.organization_id] = {
          team_ids_to_info: Set[team_info],
          org_memberships_count: 1
        }
      end
      hash
    end

    orphaned_teams.each do |org_id, val|
      DestroyTeamDependantsJob.perform_later(org_id, val[:team_ids_to_info].to_h)
    end

    send_slack_message(orphaned_teams: orphaned_teams, orphaned_org_memberships_count: orphaned_org_memberships.count)
  end

  def get_orphaned_team_memberships
    business_ids = Business.where(business_type: "enterprise_managed").pluck(:id)

    orphaned_team_memberships = T.let([], T::Array[OrganizationMembershipEntry])

    slice_size = business_slice_size
    batch_size = batched_scope_batch_size

    business_ids.each_slice(slice_size) do |business_ids_slice|
      organization_ids = Business::OrganizationMembership.where(business_id: business_ids_slice).pluck(:organization_id)

      team_ids = Team.batched_scope(:organization_id, values: organization_ids, batch_size: batch_size).pluck(:id)

      adder_ids = OrganizationMembershipEntry.batched_scope(:organization_id, values: organization_ids, batch_size: batch_size) { |scope| scope.where(adder_type: "external_team").distinct }.pluck(:adder_id)

      orphaned_team_ids = (adder_ids - team_ids)

      if orphaned_team_ids.any?
        orphaned_team_ids.each_slice(1000) do |id_batch|
          orphaned_team_memberships += OrganizationMembershipEntry.where(adder_type: "external_team", adder_id: id_batch)
        end
      end
    end

    orphaned_team_memberships
  end

  # Returns the business slice size. When flag is enabled, process one business at a time
  # to bound the organization_ids fan-out (avoids thousands of org IDs per batch).
  def business_slice_size
    if FeatureFlag.vexi.enabled?(:scan_emu_org_memberships_per_business, default: false)
      1
    else
      100
    end
  end

  # Returns the batch size for batched_scope queries. When flag is enabled, use 200
  # instead of the default 1000 to reduce query size and avoid killed queries.
  def batched_scope_batch_size
    if FeatureFlag.vexi.enabled?(:scan_emu_org_memberships_batch_200, default: false)
      200
    else
      nil # use batched_scope default (1000)
    end
  end

  def send_slack_message(orphaned_teams:, orphaned_org_memberships_count:)
    GitHub::Chatterbox.client.say!("#external-identities-ops", "Total Orphaned EMU Organization Membership Entries: #{orphaned_org_memberships_count}") unless GitHub.enterprise?

    enterprises = Business::OrganizationMembership
      .joins("INNER JOIN businesses ON businesses.id = business_organization_memberships.business_id")
      .joins("INNER JOIN users ON users.id = business_organization_memberships.organization_id")
      .where(organization_id: orphaned_teams.keys)
      .group(:business_id)
      .order(:slug)
      .pluck(:slug, "GROUP_CONCAT(organization_id)", Arel.sql("GROUP_CONCAT(users.display_login SEPARATOR ', ')"))

    enterprises.each do |slug, org_ids, org_names|
      org_ids = org_ids.split(",").map(&:to_i)
      message = <<~HEREDOC
        Orphaned EMU Organization Memberships found for Enterprise: #{slug}
        Organizations: #{org_names}
        Teams Count: #{org_ids.inject(0) { |sum, org_id| sum + orphaned_teams[org_id][:team_ids_to_info].count }}
        Organization Membership Entries Count: #{org_ids.inject(0) { |sum, org_id| sum + orphaned_teams[org_id][:org_memberships_count] }}
      HEREDOC

      GitHub::Chatterbox.client.say!("#external-identities-ops", message) unless GitHub.enterprise?
    end
  end
end
