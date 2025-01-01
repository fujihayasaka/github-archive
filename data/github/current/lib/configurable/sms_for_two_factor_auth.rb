# typed: true
# frozen_string_literal: true

module Configurable
  module SmsForTwoFactorAuth
    extend T::Helpers
    requires_ancestor { Configurable }
    requires_ancestor { Object }

    KEY = "enable_restriction_sms_for_2fa".freeze

    def sms_for_2fa_restriction_enabled?
      config.enabled?(KEY)
    end

    # disallow SMS as an option for 2FA
    # If force is true this will create a config entry
    # that sets a policy enforcing the setting for children. If not forced, any config entry will
    # be deleted.
    #
    # force: forces the setting to override any child objects
    # actor: the user making the change
    # log_event: Boolean indicating whether to instrument this event. Defaults to false.
    #
    # returns: nothing
    def enable_restriction_sms_for_2fa(actor:, force: false, log_event: false)
      # sms as a 2FA option can only be disabled if the org has 2FA required
      return unless T.unsafe(self).two_factor_requirement_enabled?

      changed = config.enable!(KEY, actor, force)

      return unless changed

      # TODO - audit log instrumentation

      GitHub.dogstats.increment("two_factor_required.#{T.must(self.class.name).underscore}_settings.enable_restriction_sms_for_2fa")
    end

    # allow SMS as an option for 2FA
    # If force is true a policy will be created
    # that applies to children.
    #
    # force: forces the setting to override any child objects
    # actor: the user making the change
    # log_event: Boolean indicating whether to instrument this event. Defaults to false.
    #
    # returns: nothing
    def disable_restriction_sms_for_2fa(actor:, force: false, log_event: false)
      changed = if force
        config.disable!(KEY, actor, force)
      else
        config.delete(KEY, actor)
      end

      return unless changed

      # TODO - audit log instrumentation
      #
      GitHub.dogstats.increment("sms_for_2fa.#{T.must(self.class.name).underscore}_settings.disable_restriction_sms_for_2fa")
    end
  end
end
