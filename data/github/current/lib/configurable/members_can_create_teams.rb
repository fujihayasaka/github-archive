# typed: true
# frozen_string_literal: true

module Configurable
  module MembersCanCreateTeams
    extend T::Helpers

    requires_ancestor { Configurable }

    KEY = "block_members_from_creating_teams".freeze
    DISABLE_ACTION = "disable_member_team_creation_permission".freeze
    ENABLE_ACTION = "enable_member_team_creation_permission".freeze
    CLEAR_ACTION = "clear_member_team_creation_permission".freeze

    # By default members can create teams
    def members_can_create_teams?
      !config.enabled?(KEY)
    end

    def allow_members_to_create_teams(force: false, actor:)
      changed = if force
        config.disable!(KEY, actor, force)
      else
        config.delete(KEY, actor)
      end
      return unless changed

      GitHub.dogstats.increment(ENABLE_ACTION)
      T.unsafe(self).instrument(ENABLE_ACTION, instrumentation_payload(actor))
    end

    def block_members_from_creating_teams(force: false, actor:)
      changed = config.enable!(KEY, actor, force)
      return unless changed

      GitHub.dogstats.increment(DISABLE_ACTION)
      T.unsafe(self).instrument(DISABLE_ACTION, instrumentation_payload(actor))
    end

    def clear_block_members_from_creating_teams_setting(actor:)
      changed = config.delete(KEY, actor)
      return unless changed

      GitHub.dogstats.increment(CLEAR_ACTION)
      T.unsafe(self).instrument(CLEAR_ACTION, instrumentation_payload(actor))
    end


    private def instrumentation_payload(actor)
      {
        user: actor,
        org: self,
      }
    end
  end
end
