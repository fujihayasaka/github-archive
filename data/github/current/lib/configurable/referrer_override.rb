# typed: true
# frozen_string_literal: true

module Configurable
  module ReferrerOverride
    extend T::Helpers

    requires_ancestor { Configurable }

    KEY = "referrer_override.enabled".freeze

    # Public: Is the referrer override enabled for the configurable?
    #
    # Returns a Boolean.
    def referrer_override_enabled?
      config.enabled?(KEY)
    end

    # Disables referrer override.
    #
    # actor: the user making the change
    #
    # returns: nothing
    def disable_referrer_override(actor:)
      return unless GitHub.enterprise?
      changed = config.delete(KEY, actor)

      return unless changed

      T.unsafe(self).instrument(:referrer_override_disable, actor: actor)
    end

    # Enables referrer override.
    #
    # actor: the user making the change
    #
    # returns: nothing
    def enable_referrer_override(actor:)
      return unless GitHub.enterprise?
      changed = config.enable!(KEY, actor)

      return unless changed

      T.unsafe(self).instrument(:referrer_override_enable, actor: actor)
    end

  end
end
