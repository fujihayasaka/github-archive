# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# This job scans for externally managed EMU teams that have been orphaned where the team has been deleted
# but the subsequent cleanup jobs failed. These orphaned teams can prevent the team members from being deleted from an organization.
class ScanEmuOrganizationMembershipsJob < ApplicationJob
  queue_as :scan_emu_organization_memberships

  schedule interval: 24.hours, condition: -> { !GitHub.enterprise? }

  retry_on_dirty_exit

  exempt_from_tenant_context_requirement

  def perform
    # We only want to get OrganizationMembershipEntries where the org exists and the team does not.
    # DestroyTeamDependantsJob can only clean up OrganizationMembershipEntries with an org that exists.
    orphaned_team_memberships = get_orphaned_team_memberships

    if orphaned_team_memberships.empty?
      orphaned_org_memberships = []
    else
      orphaned_org_memberships = OrganizationMembershipEntry
        .joins("INNER JOIN users ON users.id = organization_membership_entries.organization_id")
        .where(id: orphaned_team_memberships.map(&:id))
        .to_a

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
    # find all enterprise managed businesses
    business_ids = Business.where(business_type: "enterprise_managed").pluck(:id)

    orphaned_team_memberships = T.let([], T::Array[OrganizationMembershipEntry])

    # Split into slices of 100 to avoid query size limit
    business_ids.each_slice(100) do |business_ids_slice|
      # find all organizations for a business
      organization_ids = Business::OrganizationMembership.where(business_id: business_ids_slice).pluck(:organization_id)

      # Find all teams belonging to the organizations
      team_ids = Team.batched_scope(:organization_id, values: organization_ids).pluck(:id)

      # Find all of the "adder_ids" that are in the organization_membership_entries table for the organizations
      adder_ids = OrganizationMembershipEntry.batched_scope(:organization_id, values: organization_ids) { |scope| scope.where(adder_type: "external_team") }.pluck(:adder_id)

      # Get only the Team Ids that are in adder_ids, but not in team_ids. These will be the orphans.
      orphaned_team_ids = adder_ids - team_ids

      # Find all of the OrganizationMembershipEntries that have an adder_id that is in orphaned_team_ids
      orphaned_team_memberships += OrganizationMembershipEntry.where(adder_type: "external_team", adder_id: orphaned_team_ids) if orphaned_team_ids.any?
    end

    orphaned_team_memberships
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
