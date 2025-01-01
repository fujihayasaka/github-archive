# typed: true
# frozen_string_literal: true

class Team
  class Creator
    def self.service
      GitHub.ldap_sync_enabled? ? LdapCreator : self
    end

    def self.create_team(creator, org, attrs, maintainers:, group_mappings: [])
      service.new(creator, org).create(attrs, maintainers: maintainers, group_mappings: group_mappings)
    end

    def initialize(creator, org)
      @creator, @org = creator, org
    end

    def create(attrs, maintainers:, group_mappings:)
      team = @org.teams.build(Team.team_attributes_hash(attrs))
      team.parent_team_id = attrs[:parent_team_id] if attrs.key?(:parent_team_id)

      # Check if it's allowed to have a parent team when being linked to an identity provider group.
      # - in SCIM-enabled GHES and EMU/Proxima, it's not allowed.
      # - in non-EMU GHEC, it's allowed.
      if @org.scim_managed_enterprise? && group_mappings.present? && team.parent_team_id
        team.errors.add(:base, "This team cannot have a parent team when being linked to an identity provider group.")
        return team
      end

      parent_team = Team.find_by(id: team.parent_team_id)
      if parent_team&.enterprise_team_managed?
        team.errors.add(:base, "This team cannot have an enterprise team managed team as a parent team.")
        return team
      end

      if @creator.present?
        team.creator_id = @creator.id
      end

      yield(team) if block_given?

      if @creator.present? && @creator.can_have_granular_permissions?
        unless team.organization.resources.members.writable_by?(@creator)
          team.errors.add(:base, "This GitHub App doesn't have permissions to create teams")
          return team
        end
      end

      cannot_admin_parent_team = @creator && parent_team && !can_admin_team?(parent_team, @creator)

      if cannot_admin_parent_team
        if !parent_team.allows_change_parent_requests_from?(team)
          team.errors.add(:base, "This team cannot be requested as a parent team.")
        else
          team.parent_team_id = nil
        end
      end

      # We need to check errors specifically here because they're added
      # in the LdapCreator subclass and aren't real AR validations
      return team unless team.errors.empty? && team.valid?

      team.save!

      # When new team is created and it is linked to external_identity_team, do not create maintainer
      # since it will prevent linking of that team to an external group
      if @org.team_sync_enabled? && group_mappings.present?
        add_members_and_maintainers(team, maintainers)
        Team::GroupMapping.batch_update_mappings(team, group_mappings, actor: @creator)
      elsif @org.scim_managed_enterprise? && group_mappings.present?
        external_group_id = group_mappings[0][:group_id].to_i
        ExternalGroupTeam.create(external_group_id: external_group_id, team_id: team.id)
      else
        add_members_and_maintainers(team, maintainers)
      end

      if cannot_admin_parent_team
        ::TeamChangeParentRequest.create_initiated_by_child!(
          parent_team: parent_team,
          child_team: team,
          requester: @creator,
        )
      end

      team
    end

    def add_initial_members(team, members)
      members.each do |member|
        team.add_member member
      end
    end

    private

    def add_members_and_maintainers(team, maintainers)
      maintainers = ensure_default_maintainer(maintainers, @creator)
      add_initial_members(team, maintainers) unless maintainers.blank?

      unless team.ldap_mapped?
        maintainers.each do |member|
          team.promote_maintainer(member)
        end
      end
    end

    def ensure_default_maintainer(maintainers, creator)
      maintainers = Array.wrap(maintainers)
      maintainers.push(creator) if creator.user?
      maintainers.uniq
    end

    def can_admin_team?(team, actor)
      if actor.can_have_granular_permissions?
        team.organization.resources.members.writable_by?(actor)
      else
        team.adminable_by?(actor)
      end
    end
  end
end
