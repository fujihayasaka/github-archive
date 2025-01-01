# typed: true
# frozen_string_literal: true

class Team
  # Modifies teams.
  class Editor
    def self.service
      GitHub.ldap_sync_enabled? ? LdapEditor : self
    end

    def self.update_team(team, group_mappings: nil, **attrs)
      service.new(team, attrs[:updater]).update(attrs.except!(:updater), group_mappings: group_mappings)
    end

    def initialize(team, updater)
      @team = team
      @updater = updater
    end

    def update(attributes, group_mappings:)
      updating_parent_team = @team.parent_team_id != attributes[:parent_team_id]
      @team.assign_attributes(Team.team_attributes_hash(attributes))
      @team.parent_team_id = attributes[:parent_team_id] if attributes.key?(:parent_team_id)

      parent_team = Team.find_by(id: attributes[:parent_team_id])
      if parent_team&.enterprise_team_managed?
        business = @team.organization.business
        @team.errors.add(:base, "This team cannot have a parent team managed by an enterprise team.")
        return false
      elsif @team.enterprise_team_managed?
        business = @team.organization.business
        if @team.parent_team_id
          @team.errors.add(:base, "This team cannot have a parent team when managed by an enterprise team.")
          return false
        end
      elsif @team.scim_managed_enterprise?
        business = @team.organization.business
        if @team.parent_team_id && @team.externally_managed?
          @team.errors.add(:base, "This team cannot have a parent team when linked to an identity provider group.")
          return false
        end

        if group_mappings&.any? && @team.explicit_members?
          @team.errors.add(:base, "This team cannot be externally managed since it has explicit members.")
          return false
        end

        reconcile_external_groups(group_mappings)

        # set group mappings to nil so it does not get into team-sync code
        group_mappings = nil
      elsif not_team_mappable?(team: @team, group_mappings: group_mappings)
        @team.errors.add(:base, "This team cannot be externally managed.")
        return false
      end

      return false unless created = @team.save

      if team_mappable?(team: @team, group_mappings: group_mappings)
        Team::GroupMapping.batch_update_mappings(@team, group_mappings, actor: @updater)
      end

      created
    rescue Team::ParentChange::CannotAcquireLockError
      GitHub.dogstats.increment "team.update.lock_already_acquired"
      @team.errors.add(:base, "Whoops! There was a problem updating the team. Please try again.")
    end

    private

    def not_team_mappable?(team:, group_mappings:)
      group_mappings.present? && !team.can_be_externally_managed?
    end

    def team_mappable?(team:, group_mappings:)
      !group_mappings.nil? && team.can_be_externally_managed?
    end

    # Private: Method to reconcile added/deleted groups when team is updated
    #
    # Returns nothing
    def reconcile_external_groups(group_mappings)
      return if group_mappings.nil?
      # since the team can only be linked to a single external group
      # there will only be a single hash in group_mappings
      if @team.external_group_team.present? && group_mappings.empty?
        # Delete external group team
        @team.external_group_team.destroy
      elsif @team.external_group_team.present? && group_mappings.any?
        # Update external group team
        external_group_id = group_mappings[0][:group_id].to_i
        unless @team.external_group_team.external_group_id == external_group_id
          @team.external_group_team.external_group_id = external_group_id
          @team.external_group_team.save
        end
      elsif group_mappings.any?
        # create it
        external_group_id = group_mappings[0][:group_id].to_i
        ExternalGroupTeam.create(external_group_id: external_group_id, team_id: @team.id)
      end
    end
  end
end
