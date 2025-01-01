# typed: true
# frozen_string_literal: true

module Configurable
  module TwoFactorRequired
    include Instrumentation::Model
    extend Configurable::Async
    extend T::Helpers
    requires_ancestor { Configurable }
    requires_ancestor { Object }

    KEY = "two_factor.required".freeze

    # Public: Is the two factor requirement enabled for the configurable?
    #
    # Returns a Boolean.
    def two_factor_requirement_enabled?
      config.enabled?(KEY)
    end

    async_configurable :two_factor_requirement_enabled?

    # Public: Is the two factor requirement disabled for the configurable?
    #
    # Returns a Boolean.
    def two_factor_requirement_disabled?
      !two_factor_requirement_enabled?
    end

    # Disables two-factor authentication being required. If force is true this will create a config entry
    # that sets a policy enforcing the setting for children. If not forced, any config entry will
    # be deleted.
    #
    # force: forces the setting to override any child objects
    # actor: the user making the change
    # log_event: Boolean indicating whether to instrument this event. Defaults to false.
    #
    # returns: nothing
    def disable_two_factor_required(actor:, force: false, log_event: false)
      changed = if force
        config.disable!(KEY, actor, force)
      else
        config.delete(KEY, actor)
      end

      return unless changed

      if log_event
        instrument :disable_two_factor_requirement, actor: actor
      end
      GitHub.dogstats.increment("two_factor_required.#{self.class.name.underscore}_settings.disable")
    end

    # Enables two-factor authentication requirement. If force is true a policy will be created
    # that applies to children.
    #
    # force: forces the setting to override any child objects
    # actor: the user making the change
    # log_event: Boolean indicating whether to instrument this event. Defaults to false.
    #
    # returns: nothing
    def enable_two_factor_required(actor:, force: false, log_event: false)
      changed = config.enable!(KEY, actor, force)

      return unless changed

      if log_event
        instrument :enable_two_factor_requirement, actor: actor
      end
      GitHub.dogstats.increment("two_factor_required.#{self.class.name.underscore}_settings.enable")
    end

    # is there a policy enabling/disabling two-factor authentication?
    def two_factor_required_policy?
      !!config.final?(KEY)
    end
  end
end
