# typed: true
# frozen_string_literal: true

module EnterpriseCloudOnboard
  class SKUTrial

    class EnablementError < StandardError; end
    class WouldExpireError < StandardError; end
    class InvalidNumberOfDays < StandardError; end

    MAX_DAYS = 90

    sig { params(billable_entity: T.any(Organization, Business), sku_name: String, advanced_security_enabled_type_volume: String).void }
    def initialize(billable_entity:, sku_name:, advanced_security_enabled_type_volume:)
      @billable_entity = billable_entity
      @advanced_security_enabled_type_volume = advanced_security_enabled_type_volume
      @sku_name = sku_name
      @helper = T.let(Configurable::TrialConfigHelper.new(rec: billable_entity, sku_name: sku_name, max_days: MAX_DAYS), Configurable::TrialConfigHelper)
    end

    # If there are reasons we can't enable the trial on this enterprise, return them here.
    # Otherwise, return empty array. This method is helpful for checking preconditions before calling
    # the enable method.
    sig { params(actor: User, api_access: T::Boolean).returns(T::Array[String]) }
    def enablement_errors(actor:, api_access:)
      return ["Trial already active"] if @helper.trial_enabled?

      errors = T.let([], T::Array[String])
      errors << "Trial not supported on GitHub Enterprise" if GitHub.enterprise?
      errors << "User not authorized to enable feature" if !@billable_entity.adminable_by?(actor) && !api_access
      errors << "GHAS is in use" if ghas_is_in_use?
      errors << "Feature already in use" if feature_is_in_use?
      errors << "Organization does not have a Teams plan" if @billable_entity.organization? && !@billable_entity.plan.business?

      errors
    end

    sig { params(actor: User, days: Integer, start_date: Date, api_access: T::Boolean, sfdc_poc_url: String, reset_private_repos_on_expiration: T::Boolean).void }
    def enable(actor:, days:, start_date: Date.current, api_access: false, sfdc_poc_url: "", reset_private_repos_on_expiration: false)
      errors = enablement_errors(actor: actor, api_access: api_access)
      raise EnablementError, errors[0] if errors.length > 0
      if !days.between?(1, MAX_DAYS)
        raise InvalidNumberOfDays, "Invalid number of days: #{days}"
      end

      trial_sku = case @sku_name
      when "code_security"
        :CODE_SECURITY
      when "secret_protection"
        :SECRET_PROTECTION
      else
        :UNKNOWN_SKU
      end

      if trial_sku == :UNKNOWN_SKU
        raise EnablementError, "Unknown SKU for Trial: #{@sku_name}"
      end

      @helper.enable_trial(actor: actor, start_date: start_date, days: days, reset_on_expiration: reset_private_repos_on_expiration)

      message = {
        enterprise_id: @billable_entity.is_a?(Business) ? @billable_entity.id : nil,
        organization_id: @billable_entity.is_a?(Organization) ? @billable_entity.id : nil,
        action: :STARTED,
        trial_sku:,
        start_method: :API,
        sfdc_poc_url:,
      }
      GlobalInstrumenter.instrument("advanced_security_trial.toggled", message) if GitHub.flipper.enabled?(:advanced_security_trial_toggled_event)

    end

    sig { returns(T::Boolean) }
    def enabled?
      @helper.trial_enabled?
    end

    sig { params(actor: User).void }
    def disable(actor:)
      trial_sku = case @sku_name
      when "code_security"
        :CODE_SECURITY
      when "secret_protection"
        :SECRET_PROTECTION
      else
        :UNKNOWN_SKU
      end

      if trial_sku == :UNKNOWN_SKU
        raise EnablementError, "Unknown SKU for Trial: #{@sku_name}"
      end

      @helper.disable_trial(actor: actor)

      message = {
        enterprise_id: @billable_entity.is_a?(Business) ? @billable_entity.id : nil,
        organization_id: @billable_entity.is_a?(Organization) ? @billable_entity.id : nil,
        action: :ENDED,
        trial_sku:,
        converted_to_paid: @billable_entity.advanced_security_purchased?,
        reset_all_private_repos: reset_on_expiration?,
        **@billable_entity.advanced_security_usage_stats
      }
      GlobalInstrumenter.instrument("advanced_security_trial.toggled", message) if GitHub.flipper.enabled?(:advanced_security_trial_toggled_event)
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

      @helper.set_number_of_days(actor: actor, days: days)
    end

    sig { params(actor: User, reset_on_expiration: T::Boolean).void }
    def set_reset_on_expiration(actor:, reset_on_expiration:)
      return unless @helper.trial_enabled?
      @helper.set_reset_on_expiration(actor: actor, reset_on_expiration: reset_on_expiration)
    end

    sig { returns(T::Boolean) }
    def reset_on_expiration?
      @helper.reset_on_expiration?
    end

    sig { returns(T.nilable(Date)) }
    def started_at
      @helper.start_date
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

    sig { returns(T.any(Organization, Business)) }
    def billable_entity
      @billable_entity
    end

    sig { returns(String) }
    def sku_name
      @sku_name
    end

    sig { void }
    def reload
      @billable_entity.reload
    end

    def self.throttle(**arguments, &block)
      ::Configuration::Entry.throttle(**arguments, &block)
    end

    class << self
      protected

      sig { params(sku_name: String, batch_size: Integer).returns(T::Enumerator[T::Array[::Configuration::Entry]]) }
      def active_trial_config_entries(sku_name:, batch_size:)
        trial_key = ::Configurable::TrialConfigHelper.trial_key(sku_name)

        # The rbi for find_in_batches is wrong! It has the wrong return type. Hence the T.unsafe.
        # See https://github.com/Shopify/tapioca/issues/2239
        T.unsafe(::Configuration::Entry).named(trial_key).with_true_value.find_in_batches(batch_size: batch_size)
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
