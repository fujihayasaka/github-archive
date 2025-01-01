# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# This job scans for externally managed EMU organization members that do not have an OrganizationMembershipEntry record.
# Each organization member in EMU should have an OrganizationMembershipEntry record, entries without a record indicate
# that the job that was supposed to remove the user from an organization failed, but the record was already removed, hence
# leaving the user orphaned.
class ScanEmuOrganizationUsersJob < ApplicationJob
  queue_as :scan_emu_organization_users

  schedule interval: 24.hours, condition: -> { !GitHub.enterprise? }

  retry_on_dirty_exit

  exempt_from_tenant_context_requirement

  def perform
    GitHub.logger.info(
      "info.message" => "Starting scan_emu_organization_users job"
    )

    fix_orphaned_users

    GitHub.logger.info(
      "info.message" => "Finished scan_emu_organization_users job"
    )
  end

  private

  def fix_orphaned_users
    organization_user_map = scan_emu_organizations_for_orphaned_users
    emu_organization_ids = organization_user_map.keys || []

    GitHub.logger.info(
      "info.message" => "Looking for orphaned users",
      "gh.emu_with_orphaned_user_organization_ids" => emu_organization_ids,
    )

    unless organization_user_map.any?
      GitHub::Chatterbox.client.say!("#external-identities-ops", "No EMU Users found without Organization Membership Entry.") unless GitHub.enterprise?

      GitHub.logger.info(
        "info.message" => "Did not find any orphaned users",
        "gh.emu_with_orphaned_user_organization_ids" => emu_organization_ids,
      )

      return
    end

    fix_organization_members(organization_user_map)

    GitHub.logger.info(
      "info.message" => "Finished fixing orphaned users",
      "gh.emu_with_orphaned_users_organization_ids" => emu_organization_ids,
    )
  end

  # Private: Performs a scan for all EMUs and organizations for missing OrganizationMembershipEntry records
  #
  # Returns a Hash - keyed by organization id of all users that are missing OrganizationMembershipEntry records
  def scan_emu_organizations_for_orphaned_users
    # find all enterprise managed businesses
    business_ids = Business.where(business_type: "enterprise_managed").pluck(:id)

    organization_user_map = {}

    # Split into slices of 100 to avoid query size limit
    business_ids.each_slice(100) do |business_ids_slice|
      # find all organizations for a business
      organization_ids = Business::OrganizationMembership.where(business_id: business_ids_slice).pluck(:organization_id)

      # Find all abilities for organizations
      ability_ids = Ability.where(subject_type: "Organization", subject_id: organization_ids, actor_type: "User").pluck(:id).sort

      # find all abilities that have entries in organization memberships
      ome_ability_ids = OrganizationMembershipEntry.batched_scope(:ability_id, values: ability_ids).pluck(:ability_id)
      ome_ability_ids = ome_ability_ids.uniq.sort

      # find abilities that do not exist in organization membership entries
      missing_ability_ids = ability_ids - ome_ability_ids

      # Organization/user map with missing organization entries
      organization_user_map.merge!(Ability.where(id: missing_ability_ids).select(:subject_id, :actor_id).distinct.pluck(:subject_id, :actor_id).group_by { |i| i.shift }.transform_values { |v| v.flatten })
    end

    organization_user_map
  end

  # Private: loops over organizations and removes all of the users in stored in values from the organization.
  #
  # Returns nothing
  def fix_organization_members(organization_user_map)
    count = organization_user_map.map { |_, v| v.count }.reduce(0, :+)
    GitHub::Chatterbox.client.say!("#external-identities-ops", "Total number of Orphaned EMU User without Organization Membership Entry: #{count}") unless GitHub.enterprise?

    # loop through all organizations and remove users from them
    organization_user_map.each do |org_id, user_ids|
      org = GitHub::CurrentTenant.unscope { Organization.find_by(id: org_id) }
      next if org.nil?

      GitHub::CurrentTenant.set(org.business) do
        fix_members(org, user_ids)
      end
    end
  end

  # Private: Remove the user from the organization. This method assumes the user does not belong to any teams.
  #
  # Returns nothing
  def fix_non_team_member(org, user, user_ability_id)
    omes = OrganizationMembershipEntry.where(organization_id: org.id, user_id: user.id, adder_type: :admin)
    ome = omes.first

    if ome.present? && user_ability_id.present? && user_ability_id != ome.ability_id
      GitHub.logger.info(
        "info.message" => "Updating incorrectly recorded ability_id for user organization membership entry",
        "gh.business.id" => org.business&.id,
        "gh.organization.id" => org.id,
        "gh.organization_membership_entry.id" => ome.id,
        "gh.user.id" => user.id,
      )

      ome.update(ability_id: user_ability_id)
    else
      org.remove_member(user)
    end
  end

  # Private: Removes all of the users in stored in values from the organization.
  #
  # Returns nothing
  def fix_members(org, user_ids)
    return if org.nil?
    users = User.where(id: user_ids)

    # All teams that belong to this organization
    organization_teams = Team.where(organization_id: org.id).to_h { |t| [t.id, t] }
    externally_managed_team_ids = Team.where(id: organization_teams.keys).joins(:external_group_team).pluck(:id)

    # Users that have teams, will need to check if those teams are part of the organization
    users_with_teams_ids = Ability.where(subject_type: "Team", actor_type: "User", actor_id: user_ids, subject_id: organization_teams.keys).pluck(:actor_id, :subject_id).group_by { |i| i.shift }.transform_values { |v| v.flatten }

    GitHub::Chatterbox.client.say!("#external-identities-ops", "Number of Orphaned EMU User without Organization Membership Entry for organization #{org.login}: #{user_ids.size}") unless GitHub.enterprise? # rubocop:disable GitHub/DoNotAllowLogin used for logging

    ability_ids = Ability.where(subject_type: "Organization", subject_id: org.id, actor_type: "User").pluck(:actor_id, :id).group_by { |i| i.shift }.transform_values { |v| v.flatten.first }

    with_write do
      users.each do |user|
        teams = users_with_teams_ids[user.id]

        if teams&.any?
          OrganizationMembershipEntry.where(organization_id: org.id, user_id: user.id).where.not(ability_id: ability_ids[user.id]).delete_all

          # user is part a member of a team, need to add missing organization membership entry
          teams.each do |team_id|
            if externally_managed_team_ids.include?(team_id)
              org.add_organization_membership_entry(user: user, team: organization_teams[team_id], adder: team_id)
            else
              org.add_organization_membership_entry(user: user)
            end
          end
        else
          begin
            user_ability_id = ability_ids[user.id]
            fix_non_team_member(org, user, user_ability_id)
          rescue Organization::BusinessTeamsDependency::UnableToRemoveBusinessTeamMemberError, Organization::NoAdminsError, Organization::UnableToRemoveEmuError, Organization::UnableToRemoveEnterpriseTeamMemberError => error
            GitHub::Chatterbox.client.say!("#external-identities-ops", "Failed to remove user: #{user.login} message: #{error.message}") # rubocop:disable GitHub/DoNotAllowLogin used for logging
          end
        end
      end
    end
  end
end
