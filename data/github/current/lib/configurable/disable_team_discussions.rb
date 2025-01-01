# typed: false
# frozen_string_literal: true

module Configurable
  module DisableTeamDiscussions
    extend Configurable::Async

    KEY = "team_discussions.disable".freeze

    async_configurable :team_discussions_allowed?
    def team_discussions_allowed?
      !config.enabled?(KEY)
    end

    # Disables team discussions by ensuring that the disabled key is present.
    def disallow_team_discussions(force = false, actor:)
      changed = config.enable!(KEY, actor, force)
      return unless changed

      GitHub.dogstats.increment("team_discussions.disable")
      GitHub.instrument(
        "team_discussions.disable",
        instrumentation_payload(actor))
    end

    # Enables team discussions by removing or disabling the disabled key.
    def allow_team_discussions(force = false, actor:)
      changed = if force
        # to force a settings value, the setting value must exist
        config.disable!(KEY, actor, force)
      else
        config.delete(KEY, actor)
      end

      return unless changed

      GitHub.dogstats.increment("team_discussions.enable")
      GitHub.instrument(
        "team_discussions.enable",
        instrumentation_payload(actor))
    end

    # Clears the team discussions setting, removing any value from inheritance
    # hierarchy
    def clear_team_discussions_setting(actor:)
      changed = config.delete(KEY, actor)
      return unless changed

      GitHub.dogstats.increment("team_discussions.clear")
      GitHub.instrument(
        "team_discussions.clear",
        instrumentation_payload(actor))
    end

    # Returns whether the configuration entry has a policy enforcement
    def team_discussions_policy?
      !!config.final?(KEY)
    end

    private def instrumentation_payload(actor)
      payload = { user: actor }

      if self.is_a?(Organization)
        payload[:org] = self
        payload[:business] = self.business if self.business
      elsif self.is_a?(Business)
        payload[:business] = self
      end

      payload
    end
  end
end
