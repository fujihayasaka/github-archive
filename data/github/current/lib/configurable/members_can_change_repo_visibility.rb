# typed: false
# frozen_string_literal: true

module Configurable
  module MembersCanChangeRepoVisibility
    KEY = "block_members_from_changing_repo_visibility".freeze

    # Default value is true
    def members_can_change_repo_visibility?(to_public: false)
      !config.enabled?(KEY)
    end

    # Default is enabled.
    #
    # Therefore we delete the key to enable the setting or `disable!`
    # when force is passed as true.
    def allow_members_to_change_repo_visibility(force: false, actor:)
      changed = if force
        # To force a settings value, the setting value must exist
        config.disable!(KEY, actor, force)
      else
        config.delete(KEY, actor)
      end

      return unless changed

      GitHub.dogstats.increment("repository_visibility_change.enable")
      GitHub.instrument(
        "repository_visibility_change.enable",
        instrumentation_payload(actor))
    end

    def block_members_from_changing_repo_visibility(force: false, actor:)
      changed = config.enable!(KEY, actor, force)
      return unless changed

      GitHub.dogstats.increment("repository_visibility_change.disable")
      GitHub.instrument(
        "repository_visibility_change.disable",
        instrumentation_payload(actor))
    end

    def clear_members_can_change_repo_visibility_setting(actor:)
      changed = config.delete(KEY, actor)
      return unless changed

      GitHub.dogstats.increment("repository_visibility_change.clear")
      GitHub.instrument(
        "repository_visibility_change.clear",
        instrumentation_payload(actor))
    end

    # Is the setting enforced by a policy
    #
    # Returns a Boolean, true when the setting is enforced by policy, otherwise
    # false.
    def members_can_change_repo_visibility_policy?
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
