# typed: true
# frozen_string_literal: true

# This configurable tracks the single enterprise team that is the "copilot" team for all users in the enterprise.
# This is used in the Azure DevOps copilot integration.
module Configurable
  module AllUsersCopilotTeam
    extend T::Helpers

    requires_ancestor { Configurable }
    requires_ancestor { Kernel }

    KEY = "all_users_copilot_team".freeze
    SET_INSTRUMENTATION_KEY = "business.set_all_users_copilot_team"
    UNSET_INSTRUMENTATION_KEY = "business.unset_all_users_copilot_team"

    UNSUPPORTED_ENTERPRISE_ERROR = "All users copilot team is not supported for this enterprise."
    ENTERPRISE_OWNER_REQUIRED_ERROR = "All users copilot team can only be configured by an enterprise owner."

    # Raise when all users copilot team has issues when configuring.
    class AllUsersCopilotTeamError < StandardError; end

    # Sets an enterprise team as the all users copilot team.
    def set_all_users_copilot_team(actor: nil, enterprise_team_id:)
      unless eligible_for_all_users_copilot_team?
        raise AllUsersCopilotTeamError.new UNSUPPORTED_ENTERPRISE_ERROR
      end

      T.bind(self, Business)
      unless self.owner?(actor)
        raise AllUsersCopilotTeamError.new ENTERPRISE_OWNER_REQUIRED_ERROR
      end

      team, error = find_and_validate_team(enterprise_team_id)
      if error.present?
        raise AllUsersCopilotTeamError.new error
      end

      enterprise_team_id_from = all_users_copilot_team_id

      return unless config.set!(KEY, enterprise_team_id, actor)

      # start a job to update enterprise team copilot assignment
      EnterpriseTeamAllUsersCopilotTeamJob.perform_later(enterprise_team_id_from: enterprise_team_id_from,
        enterprise_team_id_to: enterprise_team_id)
      instrument_all_users_copilot_team(name: SET_INSTRUMENTATION_KEY, actor: actor, enterprise_team: team)
    end

    # Unsets the all users copilot team.
    def unset_all_users_copilot_team(actor: nil)
      unless eligible_for_all_users_copilot_team?
        raise AllUsersCopilotTeamError.new UNSUPPORTED_ENTERPRISE_ERROR
      end

      T.bind(self, Business)
      unless self.owner?(actor)
        raise AllUsersCopilotTeamError.new ENTERPRISE_OWNER_REQUIRED_ERROR
      end

      # return early if there's not an existing all users copilot team rather than throwing an error
      unless all_users_copilot_team_enabled?
        return
      end

      enterprise_team_id_from = all_users_copilot_team_id

      return unless config.delete(KEY, actor)

      EnterpriseTeamAllUsersCopilotTeamJob.perform_later(enterprise_team_id_from: enterprise_team_id_from,
        enterprise_team_id_to: nil)
      instrument_all_users_copilot_team(name: UNSET_INSTRUMENTATION_KEY, actor: actor)
    end

    def all_users_copilot_team_enabled?
      config.int(KEY).present?
    end

    def all_users_copilot_team_id
      config.int(KEY)
    end

    private

    def eligible_for_all_users_copilot_team?
      return false if GitHub.enterprise?
      return false if GitHub.multi_tenant_enterprise?
      return false unless self.is_a?(Business)
      return false unless self.enterprise_managed_user_enabled?

      true
    end

    def find_and_validate_team(enterprise_team_id)
      team = EnterpriseTeam.find_by(id: enterprise_team_id)

      unless team.present?
        return nil, "Enterprise team not found."
      end

      unless team.business == self
        return nil, "Enterprise team's business does not match the enterprise."
      end

      if team.enterprise_team_memberships.any?
        return nil, "Enterprise team cannot have any members when it's set as the all users copilot team."
      end

      if team.enterprise_team_organization_mappings.any?
        return nil, "All users copilot team cannot be mapped to an organization."
      end

      if team.enterprise_team_group_mappings.any?
        return nil, "All users copilot team cannot be mapped to an external group."
      end

      [team, nil]
    end

    def instrument_all_users_copilot_team(name:, actor:, enterprise_team: nil)
      payload = {
        actor: actor,
        business: self,
      }

      payload.merge!({ enterprise_team: enterprise_team }) if enterprise_team.present?

      GitHub.instrument(name, payload)
    end
  end
end
