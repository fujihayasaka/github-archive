# typed: true
# frozen_string_literal: true

module Configurable
  module ActionsCustomImagesAllowedByOwner
    extend T::Helpers

    requires_ancestor { Configurable }

    include Instrumentation::Model

    KEY = "actions_custom_images_allowed_by_owner".freeze

    def allow_custom_images(actor:)
      old_policy = custom_images_allowed_by_owner?
      config.enable(KEY, actor)
      instrument_custom_images_policy_change(actor: actor, old_policy: old_policy, new_policy: true)
    end

    def disallow_custom_images(actor:)
      old_policy = custom_images_allowed_by_owner?
      config.disable(KEY, actor)
      instrument_custom_images_policy_change(actor: actor, old_policy: old_policy, new_policy: false)
    end

    private

    def instrument_custom_images_policy_change(actor:, old_policy:, new_policy:)
      return if old_policy == new_policy
      return unless FeatureFlag.vexi.enabled?(:audit_log_org_custom_images_policy, actor, default: false)

      instrument "update_custom_images_policy",
        actor: actor,
        old_policy: old_policy ? "enabled" : "disabled",
        new_policy: new_policy ? "enabled" : "disabled"
    end

    public

    # used for testing
    def clear_custom_images_allowed(actor:)
      config.delete(KEY, actor)
    end

    # This means that the setting has to be explicitly set to `true` in order to
    # be considered enabled. `nil` is equivalent to `false`. Inherited values are ignored.
    def custom_images_allowed_by_owner?
      !!config.local?(KEY) && config.enabled?(KEY)
    end
  end
end
