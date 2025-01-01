# typed: strict
# frozen_string_literal: true

# Whether a customer (enterprise account or org) has joined GitHub Advanced Security Trial
module Configurable
  module AdvancedSecurityTrialConfig
    extend T::Helpers

    requires_ancestor { Configurable }
    requires_ancestor { ActiveRecord::Base }

    ADVANCED_SECURITY_TRIAL_KEY = "advanced_security_trial"
    ADVANCED_SECURITY_TRIAL_DAYS_KEY = "advanced_security_trial_number_of_days"
    ADVANCED_SECURITY_TRIAL_EXPIRES_AT_KEY = "advanced_security_trial_expires_at"
    ADVANCED_SECURITY_TRIAL_MAX_DAYS = 90

    sig { params(actor: User).returns(T::Boolean) }
    def enable_advanced_security_trial_for_entity(actor:)
      config.enable(ADVANCED_SECURITY_TRIAL_KEY, actor)
    end

    sig { params(actor: User).returns(T::Boolean) }
    def disable_advanced_security_trial_for_entity(actor:)
      config.delete(ADVANCED_SECURITY_TRIAL_KEY, actor)
    end

    sig { returns(T::Boolean) }
    def advanced_security_trial_enabled_for_entity?
      return false if new_record?
      return false unless config.local?(ADVANCED_SECURITY_TRIAL_KEY)

      config.enabled?(ADVANCED_SECURITY_TRIAL_KEY)
    end

    sig { params(actor: User, days: Integer).returns(T::Boolean) }
    def set_advanced_security_trial_number_of_days(actor:, days:)
      days = [days.abs, ADVANCED_SECURITY_TRIAL_MAX_DAYS].min
      config.set(ADVANCED_SECURITY_TRIAL_DAYS_KEY, days, actor)
    end

    sig { params(actor: User).returns(T::Boolean) }
    def delete_advanced_security_trial_number_of_days(actor:)
      config.delete(ADVANCED_SECURITY_TRIAL_DAYS_KEY, actor)
    end

    sig { params(actor: User, date: Date).returns(T::Boolean) }
    def set_advanced_security_trial_expires_at(actor:, date:)
      config.set(ADVANCED_SECURITY_TRIAL_EXPIRES_AT_KEY, date, actor)
    end

    sig { returns(T.nilable(Date)) }
    def get_advanced_security_trial_expires_at
      config.get(ADVANCED_SECURITY_TRIAL_EXPIRES_AT_KEY)&.to_date
    end

    sig { params(extended_days: Integer, actor: User).returns(T::Boolean) }
    def extend_advanced_security_trial_expires_at(extended_days:, actor:)
      config_date = config.get(ADVANCED_SECURITY_TRIAL_EXPIRES_AT_KEY)&.to_date
      return false unless config_date

      config.set(ADVANCED_SECURITY_TRIAL_EXPIRES_AT_KEY, config_date + extended_days.days, actor)
    end

    sig { returns(Integer) }
    def advanced_security_trial_number_of_days
      config.get(ADVANCED_SECURITY_TRIAL_DAYS_KEY)&.to_i || ADVANCED_SECURITY_TRIAL_MAX_DAYS
    end
  end
end
