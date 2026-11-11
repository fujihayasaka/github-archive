# typed: true
# frozen_string_literal: true

module EnterpriseCloudOnboard
  class SKUTrial
    include GitHub::Memoizer

    class EnablementError < StandardError; end
    class WouldExpireError < StandardError; end
    class InvalidNumberOfDays < StandardError; end

    MAX_DAYS = 120
    BATCH_SIZE = 1000
    COOLDOWN_PERIOD_DAYS = 180  # 6 months
    COOLDOWN_PERIOD_DAYS_SHORT = 0  # 0 days for staff testing (allows same-day trials)
    MAX_TRIAL_COUNT = 2
    SELF_SERVE_TRIAL_MAX_SEATS = 100
    BUNDLED_GHAS_ERROR = "Bundled GHAS customers must transition to unbundled before starting a trial"

    sig { params(billable_entity: T.any(Organization, Business), sku_name: String, advanced_security_enabled_type_volume: String, trial_type: Symbol).void }
    def initialize(billable_entity:, sku_name:, advanced_security_enabled_type_volume:, trial_type: :sales_led)
      @billable_entity = billable_entity
      @advanced_security_enabled_type_volume = advanced_security_enabled_type_volume
      @sku_name = sku_name
      @trial_type = T.let(trial_type, Symbol)
      @helper = T.let(Configurable::TrialConfigHelper.new(rec: billable_entity, sku_name: sku_name, max_days: MAX_DAYS), Configurable::TrialConfigHelper)
    end

    # If there are reasons we can't enable the trial on this enterprise, return them here.
    # Otherwise, return empty array. This method is helpful for checking preconditions before calling
    # the enable method.
    sig { params(actor: User, api_access: T::Boolean, stafftools_access: T::Boolean).returns(T::Array[String]) }
    def enablement_errors(actor:, api_access:, stafftools_access: false)
      return ["Trial already active"] if @helper.trial_enabled?

      errors = T.let([], T::Array[String])
      errors << "Trial not supported on GitHub Enterprise" if GitHub.enterprise?
      errors << "User not authorized to enable feature" if !@billable_entity.adminable_by?(actor) && !api_access && !stafftools_access
      errors << "Organization does not have a Teams plan" if @billable_entity.organization? && !@billable_entity.plan.business?

      # Block sales-led trials for bundled GHAS customers — they must transition to unbundled first
      if @trial_type == :sales_led && FeatureFlag.vexi.enabled?(:block_bundled_ghas_sku_trials, @billable_entity, default: false)
        errors << BUNDLED_GHAS_ERROR if @billable_entity.ghas_sku_purchased_for_entity?
      end

      # Apply self-serve specific validation rules if this is a self-serve trial
      if @trial_type == :self_serve
        errors.concat(self_serve_eligibility_errors)
      end

      errors
    end

    # Check if self-serve trial feature flag is enabled for the account
    sig { returns(T::Boolean) }
    def self_serve_feature_enabled?
      FeatureFlag.vexi.enabled?(:unified_self_serve_ghas_trials, @billable_entity, default: false)
    end

    # Check if the short cooldown period feature flag is enabled for staff testing
    sig { returns(T::Boolean) }
    def short_cooldown_enabled?
      FeatureFlag.vexi.enabled?(:ghas_trial_short_cooldown_for_testing, @billable_entity, default: false)
    end

    sig { returns(T::Boolean) }
    def paid_usage_cooldown_enabled?
      FeatureFlag.vexi.enabled?(:ghas_trial_paid_usage_cooldown, @billable_entity, default: false)
    end

    # Returns the effective cooldown period in days based on feature flag
    # When short cooldown is enabled, returns 0 days (same-day trials allowed); otherwise returns 180 days
    sig { returns(Integer) }
    def effective_cooldown_period_days
      if short_cooldown_enabled?
        COOLDOWN_PERIOD_DAYS_SHORT
      else
        COOLDOWN_PERIOD_DAYS
      end
    end

    # Check if the account has reached the maximum trial count
    sig { returns(T::Boolean) }
    def trial_count_limit_reached?
      trial_count >= MAX_TRIAL_COUNT
    end

    # Check if the account is within the cooldown period after the last trial
    sig { returns(T::Boolean) }
    def within_cooldown_period?
      return false if trial_count == 0 || ended_at.nil?

      days_since_last_trial = (Date.current - T.must(ended_at)).to_i
      days_since_last_trial < effective_cooldown_period_days
    end

    # Calculate the remaining cooldown time before next trial can start
    # Returns remaining time in days, or nil if not in cooldown
    sig { returns(T.nilable(Integer)) }
    def remaining_cooldown_days
      return nil if trial_count == 0 || ended_at.nil?

      days_since_last_trial = (Date.current - T.must(ended_at)).to_i
      remaining_days = effective_cooldown_period_days - days_since_last_trial
      return nil if remaining_days <= 0

      remaining_days
    end

    # Check if the billable entity is a metered GHE business
    # Only businesses can be metered GHE - organizations use seats directly
    sig { returns(T::Boolean) }
    def metered_ghe?
      @billable_entity.is_a?(Business) && @billable_entity.metered_ghe?
    end

    # Get the GHE seat count for the billable entity, handling both volume and metered billing models
    # For volume customers: returns purchased seats (business.seats)
    # For metered customers: returns consumed enterprise licenses (actual usage)
    sig { returns(Integer) }
    def ghe_seat_count
      if metered_ghe?
        # metered_ghe? already confirms @billable_entity is a Business
        T.cast(@billable_entity, Business).consumed_enterprise_licenses
      else
        @billable_entity.seats
      end
    end

    # Check if seat count exceeds the limit for self-serve trials
    # This applies to ALL self-serve trials (including the first one)
    sig { returns(T::Boolean) }
    def seat_limit_exceeded_for_next_trial?
      ghe_seat_count > SELF_SERVE_TRIAL_MAX_SEATS
    end

    # Get detailed eligibility information for displaying in stafftools
    # Returns a hash with all eligibility check results and relevant metadata
    sig { returns(T::Hash[Symbol, T.untyped]) }
    def eligibility_details
      {
        feature_enabled: self_serve_feature_enabled?,
        trial_active: @helper.trial_enabled?,
        trial_count: trial_count,
        trial_count_limit: MAX_TRIAL_COUNT,
        trial_count_limit_reached: trial_count_limit_reached?,
        last_trial_ended_at: ended_at,
        within_cooldown_period: within_cooldown_period?,
        cooldown_period_days: effective_cooldown_period_days,
        short_cooldown_enabled: short_cooldown_enabled?,
        paid_usage_cooldown_enabled: paid_usage_cooldown_enabled?,
        remaining_cooldown_days: remaining_cooldown_days,
        current_seats: ghe_seat_count,
        self_serve_trial_max_seats: SELF_SERVE_TRIAL_MAX_SEATS,
        seat_limit_exceeded: seat_limit_exceeded_for_next_trial?,
        metered_ghe: metered_ghe?,
        ghas_in_use: ghas_is_in_use? || feature_is_in_use?,
        had_paid_ghas_usage_within_cooldown: had_paid_ghas_usage_within_cooldown?,
        trial_type: @trial_type,
        eligible: self_serve_eligibility_errors.empty?
      }
    end

    # Self-serve trial validation rules. Returns array of error messages.
    # Note: Metered GHEC customers are now eligible for self-serve GHAS trials (expansion from previous restriction
    # in the old system). No additional validation needed for them as they're allowed regardless of enterprise trial status
    sig { returns(T::Array[String]) }
    def self_serve_eligibility_errors
      errors = T.let([], T::Array[String])

      # Check feature flag
      unless self_serve_feature_enabled?
        errors << "Self-serve trials are not enabled for this account"
        return errors # Exit early if feature flag is disabled
      end

      # Check if a trial is already active (includes DFD, sales-led, etc.)
      if @helper.trial_enabled?
        errors << "Trial already active"
        return errors # Exit early if trial is already running
      end

      # Trial count limit: max 2 trials per account lifetime
      if trial_count_limit_reached?
        errors << "Maximum trial limit reached (#{MAX_TRIAL_COUNT} trials)"
      end

      # Cooldown period: 180 days (6 months) between trials
      if within_cooldown_period?
        remaining_days = T.must(remaining_cooldown_days)
        errors << "Must wait #{remaining_days} more days before next trial (180-day cooldown)"
      end

      # Seat limits for self-serve trials: ≤100 GHE seats
      if seat_limit_exceeded_for_next_trial?
        seat_label = metered_ghe? ? "consumed GHE seats" : "GHE seats"
        errors << "Account has #{ghe_seat_count} #{seat_label}, but self-serve trials require ≤#{SELF_SERVE_TRIAL_MAX_SEATS} seats"
      end

      # Zero existing GHAS usage requirement (checks both bundled and unbundled usage)
      if ghas_is_in_use? || feature_is_in_use?
        errors << "Account has existing GHAS usage - self-serve trials require zero usage"
      end

      # Paid usage cooldown: block trials if the account had paid GHAS usage within the cooldown period
      if had_paid_ghas_usage_within_cooldown?
        errors << "Account had paid GHAS usage within the last #{effective_cooldown_period_days} days"
      end

      errors
    end

    sig { params(actor: User, days: Integer, start_date: Date, api_access: T::Boolean, stafftools_access: T::Boolean, sfdc_poc_url: String, reset_private_repos_on_expiration: T::Boolean).void }
    def enable(actor:, days:, start_date: Date.current, api_access: false, stafftools_access: false, sfdc_poc_url: "", reset_private_repos_on_expiration: true)
      errors = enablement_errors(actor: actor, api_access: api_access, stafftools_access: stafftools_access)
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

      # An edge case where the billable entity was explicitly moved to GHAS off.
      # We consider starting a trial a signal to move them back to unbundled metered.
      # This also triggers the appropriate changes to their security configurations
      # since off means bundled security configs and a trial/unbundled-metered needs
      # unbundled configs.
      if @billable_entity.advanced_security_enabled_type_for_entity == Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_OFF
        @billable_entity.set_customer_to_split_metered_offering(actor:)
      end

      capture_enabled_private_repos

      # Capture security configurations that are set as default for private repos before trial starts
      capture_default_private_repo_configurations

      # Capture security configurations that are set as default for private repos before trial starts
      capture_default_private_repo_configurations

      @helper.enable_trial(actor: actor, start_date: start_date, days: days, reset_on_expiration: reset_private_repos_on_expiration)

      # Store the trial type in the configuration
      @helper.set_trial_type(actor: actor, trial_type: @trial_type)

      start_method = case @trial_type
      when :digital_front_door then :DFD
      when :self_serve, :ghas_stand_alone then :SELF_SERVE
      else :API
      end

      message = {
        enterprise_id: @billable_entity.is_a?(Business) ? @billable_entity.id : nil,
        organization_id: @billable_entity.is_a?(Organization) ? @billable_entity.id : nil,
        customer_id: Licensing::Customer.id_for(@billable_entity),
        action: :STARTED,
        trial_sku:,
        start_method:,
        sfdc_poc_url:,
        trial_start_date: start_date,
      }
      GlobalInstrumenter.instrument("advanced_security_trial.toggled", message)
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

      # Capture usage stats BEFORE any reset happens to avoid race conditions
      pre_reset_stats = @billable_entity.advanced_security_usage_stats

      reset_on_expiration = reset_on_expiration?

      # Compute retained counts: if repos will be reset, retained is 0; otherwise count private repos only
      # (public repos don't consume GHAS licenses so they're free and shouldn't be counted as "retained")
      if reset_on_expiration
        retained_stats = {
          secret_protection_retained_private_repos: 0,
          code_security_retained_private_repos: 0,
          secret_protection_retained_committers: 0,
          code_security_retained_committers: 0,
        }
      else
        retained_stats = {
          secret_protection_retained_private_repos: pre_reset_stats[:secret_protection_private_repos_enabled] || 0,
          code_security_retained_private_repos: pre_reset_stats[:code_security_private_repos_enabled] || 0,
          secret_protection_retained_committers: pre_reset_stats[:secret_protection_committers_active] || 0,
          code_security_retained_committers: pre_reset_stats[:code_security_committers_active] || 0,
        }
      end

      # Capture trial dates before disabling (disable clears some config)
      trial_start = started_at
      trial_end = Date.current

      @helper.disable_trial(actor: actor)

      message = {
        enterprise_id: @billable_entity.is_a?(Business) ? @billable_entity.id : nil,
        organization_id: @billable_entity.is_a?(Organization) ? @billable_entity.id : nil,
        customer_id: Licensing::Customer.id_for(@billable_entity),
        action: :ENDED,
        trial_sku:,
        converted_to_paid: @billable_entity.advanced_security_purchased?,
        reset_all_private_repos: reset_on_expiration,
        trial_start_date: trial_start,
        trial_end_date: trial_end,
        **retained_stats,
        **pre_reset_stats
      }
      GlobalInstrumenter.instrument("advanced_security_trial.toggled", message)
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

    # Returns the date when the trial ended (persisted after trial cleanup)
    sig { returns(T.nilable(Date)) }
    def ended_at
      @helper.ended_at
    end

    # Returns the number of trials that have been used for this SKU
    sig { returns(Integer) }
    def trial_count
      @helper.trial_count
    end

    # Returns true if the trial is both enabled and not expired
    sig { returns(T::Boolean) }
    def trial_active?
      @helper.trial_active?
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

    sig { returns(Symbol) }
    def trial_type
      # Return the stored trial_type from config if available, otherwise fall back to instance variable
      @helper.trial_type || @trial_type
    end

    # Increment trial count
    sig { params(actor: User).void }
    def increment_trial_count(actor:)
      @helper.increment_trial_count(actor: actor)
    end

    # Set the ended_at date
    sig { params(actor: User, date: Date).void }
    def set_ended_at(actor:, date:)
      @helper.set_ended_at(actor: actor, date: date)
    end

    sig { void }
    def capture_enabled_private_repos
      SecurityProductsEnablement::PreGhasSKUTrialEnabledRepository.capture_enabled_private_repos(
        billable_entity: @billable_entity,
        sku_name: @sku_name
      )
    end

    sig { void }
    def capture_default_private_repo_configurations
      # Map trial_type to the enum values expected by PreGhasTrialDefaultPrivateRepoSecurityConfiguration
      mapped_trial_type = case @trial_type
      when :ghas_stand_alone
        :self_led
      when :digital_front_door
        :dfd
      else
        @trial_type
      end

      SecurityProductsEnablement::PreGhasTrialDefaultPrivateRepoSecurityConfiguration.capture_default_private_repo_configurations(
        billing_entity: @billable_entity,
        sku_name: @sku_name,
        trial_type: mapped_trial_type
      )
    end

    # Check if entity had any paid GHAS usage within the cooldown period (180 days by default).
    # This prevents former paying customers from immediately starting a free trial after cancelling.
    # Returns true if any billable usage (licenses > 0) is found within the cooldown window,
    # regardless of current usage state.
    sig { returns(T::Boolean) }
    memoize def had_paid_ghas_usage_within_cooldown?
      return false unless paid_usage_cooldown_enabled?

      cooldown_days = effective_cooldown_period_days
      return false if cooldown_days == 0

      customer = billable_entity.customer
      return false if customer.nil?

      # Fast path: if there are no paid GHAS line items at all, skip the expensive Billing Platform API calls
      return false if billable_entity.never_billed_for_self_serve_advanced_security?

      billing_platform_client = Billing::Platform::Api::Client.new

      check_date = Date.current.beginning_of_month
      cutoff_date = Date.current - cooldown_days.days

      result = T.let(false, T::Boolean)
      while check_date >= cutoff_date.beginning_of_month
        if has_any_ghas_usage_in_month?(billing_platform_client, customer, check_date)
          result = true
          break
        end
        check_date = (check_date - 1.month).beginning_of_month
      end

      GitHub.dogstats.increment(
        "ghas_trial.paid_usage_cooldown.check",
        tags: [
          "result:#{result}",
        ]
      )
      GitHub.logger.info("GHAS trial paid usage cooldown check",
        result: result,
        business_id: billable_entity.id,
        business_slug: billable_entity.try(:slug),
        cooldown_days: cooldown_days,
      )

      result
    end

    # Check if entity had billable usage for this specific SKU more than 30 days ago.
    # Returns true if feature is in use OR GHAS is in use AND any billable usage found from 31 days ago
    # backward to the start of that month.
    # If no usage found, it checks the month prior to the cutoff date month.
    sig { returns(T::Boolean) }
    def was_billed_more_than_30_days_ago?
      return false unless feature_is_in_use? || ghas_is_in_use?

      customer = billable_entity.customer
      return false if customer.nil?

      # Calculate the cutoff date (31 days ago from today)
      cutoff_date = Date.current - 31.days

      # Calculate the start of the month containing the cutoff date
      start_of_month = cutoff_date.beginning_of_month

      billing_platform_client = Billing::Platform::Api::Client.new

      # Check each day from cutoff_date backward to start_of_month
      current_check_date = cutoff_date
      while current_check_date >= start_of_month
        return true if has_usage_on_date?(billing_platform_client, customer, current_check_date)
        current_check_date -= 1.day
      end

      # If no daily usage found, check for any usage in the month prior to the cutoff date month as fallback
      prior_month_start = (cutoff_date - 1.month).beginning_of_month
      has_usage_in_month?(billing_platform_client, customer, prior_month_start)
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

    # This must return the number of seats for this feature that are in use.
    sig { returns(Integer) }
    def seats_used
      raise NotImplementedError
    end

    # Returns the license type for this billable entity
    sig { returns(String) }
    def license_type
      return "metered" if @billable_entity.advanced_security_metered_for_entity?
      return "volume" if @billable_entity.advanced_security_volume_for_entity?
      "off" # default when no advanced security is purchased
    end

    # Returns whether this billable entity is using bundled or unbundled licensing
    sig { returns(T::Boolean) }
    def bundled?
      # Bundled: GHAS SKU is purchased (GHAS_VOLUME or GHAS_METERED)
      return true if @billable_entity.ghas_sku_purchased_for_entity?

      # Unbundled: Either code security or secret protection are purchased separately
      return false if @billable_entity.code_security_purchased_for_entity? || @billable_entity.secret_protection_purchased_for_entity?

      # Default fallback to bundled
      true
    end

    private

    sig { returns(String) }
    def billing_sku_name
      # If using bundled GHAS, always query the bundled SKU regardless of specific feature
      if ghas_is_in_use?
        return GitHub::Turboghas::SKU::Bundled.emission_sku
      end

      # For unbundled/split SKUs, query the specific feature SKU
      case @sku_name
      when "secret_protection"
        GitHub::Turboghas::SKU::SecretSecurity.emission_sku
      when "code_security"
        GitHub::Turboghas::SKU::CodeSecurity.emission_sku
      else
        raise NotImplementedError, "Unknown SKU name: #{@sku_name}"
      end
    end

    # Check if there was billable usage on a specific date
    def has_usage_on_date?(billing_client, customer, date)
      # Query daily usage data for the specific date
      usage_response = billing_client.get_usage_chart_data(
        usage_entity_id: customer.id,
        product: "ghas",
        sku: billing_sku_name,
        year: date.year,
        month: date.month,
        day: date.day,
        billing_period: BillingPlatform::Base::BillingPeriod::Daily
      )
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed, Billing::Platform::Api::Error => e
      # Log billing API errors and return false as safe default
      Failbot.report(e, context: { customer_id: customer.id, date: date, sku: billing_sku_name })
      false
    else
      # Skip if API returned an error response
      return false if usage_response.is_a?(Billing::Platform::Api::Error)

      # Check for usage in the response
      has_usage_in_chart_data?(usage_response)
    end

    # Check if there was billable usage in a specific month
    def has_usage_in_month?(billing_client, customer, month_start)
      # Query monthly usage data for the month
      usage_response = billing_client.get_usage_chart_data(
        usage_entity_id: customer.id,
        product: "ghas",
        sku: billing_sku_name,
        year: month_start.year,
        month: month_start.month,
        billing_period: BillingPlatform::Base::BillingPeriod::Monthly
      )
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed, Billing::Platform::Api::Error => e
      # Log billing API errors and return false as safe default
      Failbot.report(e, context: { customer_id: customer.id, month_start: month_start, sku: billing_sku_name })
      false
    else
      # Skip if API returned an error response
      return false if usage_response.is_a?(Billing::Platform::Api::Error)

      # Check for usage in the response
      has_usage_in_chart_data?(usage_response)
    end

    # Extract and check usage data from billing API response
    def has_usage_in_chart_data?(usage_response)
      usage_chart_data = usage_response[:usageChartData]
      return false unless usage_chart_data.present?

      # Check if there was any billable usage for this specific SKU
      usage_chart_data.any? do |chart_entry|
        data_points = chart_entry[:data] || []
        data_points.any? { |point| point[:y].to_f > 0 }
      end
    end

    ALL_GHAS_SKU_NAMES = T.let(
      GitHub::Turboghas::SKU.values.map(&:emission_sku).freeze,
      T::Array[String]
    )

    def has_any_ghas_usage_in_month?(billing_client, customer, month_start)
      ALL_GHAS_SKU_NAMES.any? do |sku_name|
        usage_response = billing_client.get_usage_chart_data(
          usage_entity_id: customer.id,
          product: "ghas",
          sku: sku_name,
          year: month_start.year,
          month: month_start.month,
          billing_period: BillingPlatform::Base::BillingPeriod::Monthly
        )
        next false if usage_response.is_a?(Billing::Platform::Api::Error)

        has_usage_in_chart_data?(usage_response)
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed, Billing::Platform::Api::Error => e
        Failbot.report(e, context: { customer_id: customer.id, month_start: month_start, sku: sku_name })
        false
      end
    end
  end # SKUTrial
end
