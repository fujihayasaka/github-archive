# typed: true
# frozen_string_literal: true

module EnterpriseCloudOnboard
  class SKUTrial

    class EnablementError < StandardError; end
    class WouldExpireError < StandardError; end
    class InvalidNumberOfDays < StandardError; end

    MAX_DAYS = 90
    BATCH_SIZE = 1000

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
    sig { params(actor: User, api_access: T::Boolean, stafftools_access: T::Boolean).returns(T::Array[String]) }
    def enablement_errors(actor:, api_access:, stafftools_access: false)
      return ["Trial already active"] if @helper.trial_enabled?

      errors = T.let([], T::Array[String])
      errors << "Trial not supported on GitHub Enterprise" if GitHub.enterprise?
      errors << "User not authorized to enable feature" if !@billable_entity.adminable_by?(actor) && !api_access && !stafftools_access
      errors << "Organization does not have a Teams plan" if @billable_entity.organization? && !@billable_entity.plan.business?

      # Prevent trial if the feature or GHAS (bundled) is already in use, unless feature flag allows bypass
      unless FeatureFlag.vexi.enabled?(:ghas_enable_trial_access_for_existing_users, @billable_entity, default: false)
        errors << "GHAS is in use" if ghas_is_in_use?
        errors << "Feature already in use" if feature_is_in_use?
      end

      errors
    end

    sig { params(actor: User, days: Integer, start_date: Date, api_access: T::Boolean, stafftools_access: T::Boolean, sfdc_poc_url: String, reset_private_repos_on_expiration: T::Boolean).void }
    def enable(actor:, days:, start_date: Date.current, api_access: false, stafftools_access: false, sfdc_poc_url: "", reset_private_repos_on_expiration: false)
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

      record_enabled_repos if FeatureFlag.vexi.enabled?(:ghas_enable_trial_access_for_existing_users, @billable_entity, default: false)

      @helper.enable_trial(actor: actor, start_date: start_date, days: days, reset_on_expiration: reset_private_repos_on_expiration)

      message = {
        enterprise_id: @billable_entity.is_a?(Business) ? @billable_entity.id : nil,
        organization_id: @billable_entity.is_a?(Organization) ? @billable_entity.id : nil,
        action: :STARTED,
        trial_sku:,
        start_method: :API,
        sfdc_poc_url:,
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

      reset_on_expiration = reset_on_expiration?
      @helper.disable_trial(actor: actor)

      message = {
        enterprise_id: @billable_entity.is_a?(Business) ? @billable_entity.id : nil,
        organization_id: @billable_entity.is_a?(Organization) ? @billable_entity.id : nil,
        action: :ENDED,
        trial_sku:,
        converted_to_paid: @billable_entity.advanced_security_purchased?,
        reset_all_private_repos: reset_on_expiration,
        **@billable_entity.advanced_security_usage_stats
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
    def record_enabled_repos
      clear_old_records

      enabled_repo_ids = get_private_repo_ids_with_sku_enabled
      records_to_insert = enabled_repo_ids.map do |repo_id|
        {
          target_id: @billable_entity.id,
          target_type: @billable_entity.class.name,
          repository_id: repo_id,
          sku_name: @sku_name,
          created_at: Time.current,
          updated_at: Time.current
        }
      end

      records_to_insert.each_slice(BATCH_SIZE) do |batch|
        SecurityProductsEnablement::PreGhasSKUTrialEnabledRepository.insert_all(batch)
      end if records_to_insert.any?
    end

    sig { void }
    def clear_old_records
      SecurityProductsEnablement::PreGhasSKUTrialEnabledRepository.where(
        target_id: @billable_entity.id,
        target_type: @billable_entity.class.name,
        sku_name: @sku_name
      ).delete_all
    end

    sig { returns(T::Array[Integer]) }
    def get_private_repo_ids_with_sku_enabled
      repository_ids = case @billable_entity
      when Organization
        @billable_entity.org_repositories.where(public: false).pluck(:id)
      when Business
        # Get both organization repositories and user namespace repositories for EMU users
        repository_ids = []

        # Add organization repository IDs
        org_ids = @billable_entity.organizations.pluck(:id)
        repository_ids.concat(Repository.where(owner_id: org_ids, public: false).pluck(:id)) if org_ids.present?

        # Add user repository IDs for EMU users
        advanced_security_feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(@billable_entity)

        if advanced_security_feature.feature_available_for_user_repositories?
          offset_id = T.let(0, Integer)

          while (user_ids = advanced_security_feature.list_enterprise_users_ids_offset(offset_id: offset_id, per_page: BATCH_SIZE)).present?
            repository_ids.concat(
              Repository.where(owner_id: user_ids, public: false).pluck(:id)
            )
            offset_id = T.must(user_ids.last)
          end
        end

        repository_ids
      end

      # Use bulk query to find enabled repositories instead of N+1 queries
      get_enabled_repo_ids_from_batch(repository_ids.to_a)
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

    sig { params(repository_ids: T::Array[Integer]).returns(T::Array[Integer]) }
    def get_enabled_repo_ids_from_batch(repository_ids)
      return [] if repository_ids.empty?

      status_column = case @sku_name
      when "code_security" then :code_scanning_alerts_status
      when "secret_protection" then :secret_scanning_alerts_status
      else return []
      end

      repository_ids.each_slice(BATCH_SIZE).flat_map do |batch_repo_ids|
        where_clause = { repository_id: batch_repo_ids }
        where_clause[status_column] = "ENABLED"
        SecurityOverviewAnalytics::FeatureStatus
          .where(**where_clause)
          .pluck(:repository_id)
      end
    end

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
  end # SKUTrial
end
