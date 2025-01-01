# typed: true
# frozen_string_literal: true

module Configurable
  module DiscussionsEnablement
    extend Configurable::Async
    extend T::Helpers
    extend T::Sig

    requires_ancestor { Configurable }

    KEY = "discussions.enable"

    async_configurable :discussions_on?

    sig { returns T::Boolean }
    def discussions_on?
      config.enabled?(KEY)
    end

    sig { returns T::Boolean }
    def discussions_ever_on?
      !config.raw(KEY).nil?
    end

    # Override in consumers to send appropriate Hydro messages for each receiver type. By default, a no-op.
    def instrument_discussion_enablement(actor:)
    end

    # Override in consumers to take action after discussions are enabled. By default, a no-op.
    sig { void }
    def discussions_were_enabled
    end

    def turn_on_discussions(actor:, force: false, instrument: true)
      changed = config.enable!(KEY, actor, force)
      return unless changed

      instrument_discussion_enablement(actor: actor) if instrument
      discussions_were_enabled
    end

    # Override in consumers to send appropriate Hydro messages for each receiver type. By default, a no-op.
    def instrument_discussion_disablement(actor:)
    end

    # Override in consumers to take action after discussions are disabled. By default, a no-op.
    sig { void }
    def discussions_were_disabled
    end

    def turn_off_discussions(actor:, force: false, instrument: true)
      changed = config.disable!(KEY, actor, force)
      return unless changed

      instrument_discussion_disablement(actor: actor) if instrument
      discussions_were_disabled
    end
  end
end
