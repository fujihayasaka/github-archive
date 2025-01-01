# typed: true
# frozen_string_literal: true

module EnterpriseCloudOnboard
  class SKUTrial

    class EnablementError < StandardError; end
    class WouldExpireError < StandardError; end
    class InvalidNumberOfDays < StandardError; end

    MAX_DAYS = 90

    sig { params(billable_entity: Business, api_access: T::Boolean, sku_name: String, advanced_security_enabled_type_volume: String).void }
    def initialize(billable_entity:, api_access:, sku_name:, advanced_security_enabled_type_volume:)
      @api_access = api_access
      @billable_entity = billable_entity
      @advanced_security_enabled_type_volume = advanced_security_enabled_type_volume
      @helper = T.let(Configurable::TrialConfigHelper.new(rec: billable_entity, sku_name: sku_name, max_days: MAX_DAYS), Configurable::TrialConfigHelper)
    end

    # If there are reasons we can't enable the trial on this enterprise, return them here.
    # Otherwise, return empty array. This method is helpful for checking preconditions before calling
    # the enable method.
    sig { params(actor: User).returns(T::Array[String]) }
    def enablement_errors(actor:)
      return ["Trial already active"] if @helper.trial_enabled?

      errors = T.let([], T::Array[String])
      errors << "Trial not supported on GitHub Enterprise" if GitHub.enterprise?
      errors << "User not authorized to enable feature" if !@billable_entity.adminable_by?(actor) && !@api_access
      errors << "GHAS is in use" if ghas_is_in_use?
      errors << "Feature already in use" if feature_is_in_use?
      errors
    end

    sig { params(actor: User, days: Integer, start_date: Date).void }
    def enable(actor:, days:, start_date: Date.current)
      errors = enablement_errors(actor: actor)
      raise EnablementError, errors[0] if errors.length > 0
      if !days.between?(1, MAX_DAYS)
        raise InvalidNumberOfDays, "Invalid number of days: #{days}"
      end

      ActiveRecord::Base.connected_to(role: :writing) do
        @helper.enable_trial(actor: actor, start_date: start_date, days: days)
      end
    end

    sig { returns(T::Boolean) }
    def enabled?
      @helper.trial_enabled?
    end

    sig { params(actor: User).void }
    def disable(actor:)
      ActiveRecord::Base.connected_to(role: :writing) do
        @helper.disable_trial(actor: actor)
      end
    end

    sig { returns(T.nilable(Integer)) }
    def number_of_days
      @helper.number_of_days
    end

    sig { params(actor: User, days: Integer).void }
    def set_number_of_days(actor:, days:)
      return unless @helper.trial_enabled?
      if !days.between?(1, MAX_DAYS)
        raise InvalidNumberOfDays, "Invalid number of days: #{days}"
      end

      # check if we'd cause the trial to expire
      new_expiry = T.must(@helper.start_date) + days.days
      if Date.current >= new_expiry
        raise WouldExpireError, "Cannot set trial length to #{days} days because it would have already expired"
      end

      ActiveRecord::Base.connected_to(role: :writing) do
        @helper.set_number_of_days(actor: actor, days: days)
      end
    end

    sig { returns(T.nilable(Date)) }
    def expires_at
      @helper.expires_at
    end

    # This is a helper that returns true iff one or more of these is true:
    #  - Feature is purchased as volume
    #  - Feature is metered and some seats are in use
    sig { returns(T::Boolean) }
    def feature_is_in_use?
      case @billable_entity.advanced_security_enabled_type_for_entity
      when Configurable::AdvancedSecurityBillingConfig::SPLIT_VOLUME, @advanced_security_enabled_type_volume
        true
      when Configurable::AdvancedSecurityBillingConfig::SPLIT_METERED
        seats_used > 0
      else
        false
      end
    end

    # This is a helper that returns true iff one or more of these is true:
    #  - GHAS is purchased as volume
    #  - GHAS is metered and some seats are in use
    sig { returns(T::Boolean) }
    def ghas_is_in_use?
      case @billable_entity.advanced_security_enabled_type_for_entity
      when Configurable::AdvancedSecurityBillingConfig::GHAS_VOLUME
        true
      when Configurable::AdvancedSecurityBillingConfig::GHAS_METERED
        @billable_entity.advanced_security_license.consumed_seats > 0
      else
        false
      end
    end

    protected

    # This must return the number of seats for this feature that are in use.
    sig { returns(Integer) }
    def seats_used
      raise NotImplementedError
    end

  end # SKUTrial
end
