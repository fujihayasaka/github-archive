# typed: true
# frozen_string_literal: true

module EnterpriseCloudOnboard
  # Service object for enabling GHAS trials using SKUTrial models.
  # Orchestrates the creation of both Secret Protection and Code Security SKU trials
  # for a billable entity (Business or Organization).
  #
  # This supports:
  # - Both DFD (digital_front_door) and standalone (ghas_stand_alone) trial sources
  # - Error handling with automatic rollback
  # - Analytics instrumentation
  # - GitHub Recommended security configuration default for public repositories
  class AdvancedSecurityTrial
    GHAS_STAND_ALONE = :ghas_stand_alone
    DFD_SELF_SERVE = :digital_front_door

    TRIAL_LENGTH_30 = 30

    class UnprocessableError < StandardError; end

    # Simple result object for trial extension that provides ends_on for controller compatibility
    class ExtendTrialResult < T::Struct
      const :ends_on, Date
    end

    sig do
      params(
        billable_entity: T.any(Business, Organization),
        actor: User,
        trial_days: Integer,
        trial_source: Symbol
      ).returns(GitHub::Result)
    end
    def self.enable_sku_based_trial(billable_entity:, actor:, trial_days:, trial_source: :ghas_stand_alone)
      # Validate organization eligibility if needed
      return GitHub::Result.error(UnprocessableError.new("GHAS is not currently enabled for organizations.")) if billable_entity.is_a?(Organization) && !billable_entity.feature_flag_enabled_or_raise?(:ghas_self_serve_orgs) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

      # Create both SKU trials
      secret_protection_trial = secret_protection_trial(billable_entity: billable_entity, trial_type: trial_source)
      code_security_trial = code_security_trial(billable_entity: billable_entity, trial_type: trial_source)

      # Enable both trials
      begin
        # Enable Secret Protection trial
        secret_protection_trial.enable(
          actor: actor,
          days: trial_days,
          api_access: false,
          stafftools_access: false
        )

        # Enable Code Security trial
        code_security_trial.enable(
          actor: actor,
          days: trial_days,
          api_access: false,
          stafftools_access: false
        )

        message = {
          enterprise_id: billable_entity.is_a?(Business) ? billable_entity.id : nil,
          organization_id: billable_entity.is_a?(Organization) ? billable_entity.id : nil,
          customer_id: Licensing::Customer.id_for(billable_entity),
          action: :STARTED,
          trial_sku: :ADVANCED_SECURITY,
          start_method: trial_source == :digital_front_door ? :DFD : :SELF_SERVE,
        }
        GlobalInstrumenter.instrument("advanced_security_trial.toggled", message)

        github_config = SecurityConfiguration.github_recommended_configuration
        if github_config
          SecurityConfigurationDefault.create_or_update_defaults(
            target: billable_entity,
            security_configuration: github_config,
            default_for_new_public_repos: true,
            default_for_new_private_repos: false
          )

          # Apply GitHub Recommended configuration to existing repos without any configuration
          apply_github_recommended_to_unattached_repos(billable_entity, github_config, actor)
        end

        # Return success - GitHub::Result expects a block that returns a value
        GitHub::Result.new { true }
      rescue EnterpriseCloudOnboard::SKUTrial::EnablementError => e
        # Rollback: Try to disable the trials that were successfully created
        begin
          secret_protection_trial.disable(actor: actor) if secret_protection_trial.enabled?
        rescue StandardError => rollback_error
          GitHub.logger.warn(
            "exception.message": "Failed to rollback Secret Protection trial: #{rollback_error.message}",
            "gh.user.id": actor.id,
            "gh.billable_entity.id": billable_entity.id,
            "gh.billable_entity.type": billable_entity.class.name
          )
        end

        begin
          code_security_trial.disable(actor: actor) if code_security_trial.enabled?
        rescue StandardError => rollback_error
          GitHub.logger.warn(
            "exception.message": "Failed to rollback Code Security trial: #{rollback_error.message}",
            "gh.user.id": actor.id,
            "gh.billable_entity.id": billable_entity.id,
            "gh.billable_entity.type": billable_entity.class.name
          )
        end

        GitHub::Result.error(
          AdvancedSecurity::Public::Subscription::UnprocessableError.new("Failed to create trial: #{e.message}")
        )
      end
    end

    sig do
      params(
        billable_entity: T.any(Business, Organization),
        github_config: SecurityConfiguration,
        actor: User
      ).void
    end
    def self.apply_github_recommended_to_unattached_repos(billable_entity, github_config, actor)
      # Collect all repos from this billable entity and its organizations that don't have any configuration
      repos_to_update = []

      # For Business entities, iterate through their organizations
      # For Organization entities, use their repositories directly
      organizations = if billable_entity.is_a?(Business)
        billable_entity.organizations
      else
        [billable_entity]
      end

      organizations.each do |org|
        org.repositories.each do |repo|
          # Skip repos that already have a configuration attached
          next if RepositorySecurityConfiguration.where(repository_id: repo.id).applied_or_attaching.any?

          # Only attach public repos to the github_config
          next unless repo.public?

          repos_to_update.push(repo)
        end
      end

      GitHub.logger.info("Applying GitHub Recommended configuration to unattached repos", {
        "gh.billable_entity.id" => billable_entity.id,
        "gh.billable_entity.type" => billable_entity.class.name,
        "gh.security_configuration.id" => github_config.id,
        "gh.security_configuration.name" => github_config.name,
        "gh.repos_to_update_count" => repos_to_update.length,
        "gh.actor.id" => actor.id
      })

      # Apply the GitHub Recommended configuration to each unattached repo
      repos_to_update.each do |repo|
        github_config.apply_to_repository(repo, actor: actor, override_existing_config: false)
      end
    end

    sig { params(billable_entity: T.any(Business, Organization)).returns(T::Boolean) }
    def self.has_active_advanced_security_trial?(billable_entity:)
      # Check if either trial is active (enabled and not expired)
      secret_protection_trial(billable_entity: billable_entity).trial_active? ||
        code_security_trial(billable_entity: billable_entity).trial_active?
    end

    # Returns the Organization on which to start a GHAS trial for the given
    # billable entity. For an Organization, returns self. For a Business, returns
    # the first organization the actor is an owner of, or nil if none.
    sig { params(billable_entity: T.any(Business, Organization), actor: User).returns(T.nilable(Organization)) }
    def self.organization_for_advanced_security_trial(billable_entity:, actor:)
      case billable_entity
      when Organization
        billable_entity
      when Business
        billable_entity.filtered_organizations(viewer: actor, viewer_role: "owner").first
      else
        T.absurd(billable_entity)
      end
    end

    sig { params(billable_entity: T.any(Business, Organization)).returns(T.nilable(Date)) }
    def self.advanced_security_free_trial_ends_on(billable_entity:)
      # Return the latest expiration date if either trial is active
      expiration_dates = []

      secret_trial = secret_protection_trial(billable_entity: billable_entity)
      expiration_dates << secret_trial.expires_at if secret_trial.trial_active?

      code_trial = code_security_trial(billable_entity: billable_entity)
      expiration_dates << code_trial.expires_at if code_trial.trial_active?

      return nil if expiration_dates.empty?

      # Return the latest expiration date (both trials should have the same expiration)
      expiration_dates.compact.max
    end

    sig { params(billable_entity: T.any(Business, Organization)).returns(T.nilable(Integer)) }
    def self.advanced_security_trial_days_left(billable_entity:)
      secret_trial = secret_protection_trial(billable_entity: billable_entity)
      current_trial = if secret_trial.trial_active?
        secret_trial
      else
        code_trial = code_security_trial(billable_entity: billable_entity)
        code_trial if code_trial.trial_active?
      end

      return nil if current_trial.nil?
      number_of_days = current_trial.number_of_days
      started_at = current_trial.started_at
      return nil if number_of_days.nil? || started_at.nil?

      # Date subtraction returns Rational, but Sorbet's stdlib types it as Date
      days_since_start = T.unsafe(Date.current - started_at).to_i
      [number_of_days - days_since_start, 0].max
    end

    # Returns the total duration of the active trial in days
    sig { params(billable_entity: T.any(Business, Organization)).returns(T.nilable(Integer)) }
    def self.advanced_security_trial_duration_days(billable_entity:)
      # Return the trial duration from whichever trial is active
      # Both trials should have the same duration since they're started together
      secret_trial = secret_protection_trial(billable_entity: billable_entity)
      return secret_trial.number_of_days if secret_trial.trial_active?

      code_trial = code_security_trial(billable_entity: billable_entity)
      return code_trial.number_of_days if code_trial.trial_active?

      nil
    end

    # Returns the most recent ended_at date from the SKU trials
    # Used to determine if a recently ended trial should still show onboarding UI
    sig { params(billable_entity: T.any(Business, Organization)).returns(T.nilable(Date)) }
    def self.trial_ended_at(billable_entity:)
      secret_protection_trial = secret_protection_trial(billable_entity: billable_entity)
      code_security_trial = code_security_trial(billable_entity: billable_entity)

      ended_dates = [secret_protection_trial.ended_at, code_security_trial.ended_at].compact
      return nil if ended_dates.empty?

      # Return the most recent ended_at date
      ended_dates.max
    end

    sig { params(billable_entity: T.any(Business, Organization)).returns(T::Hash[Symbol, T.nilable(Date)]) }
    def self.active_ghas_trials_data_for_entity(billable_entity:)
      expiration_data = {}

      secret_trial = secret_protection_trial(billable_entity: billable_entity)
      expiration_data[:secret_protection_trial] = secret_trial.expires_at if secret_trial.trial_active?

      code_trial = code_security_trial(billable_entity: billable_entity)
      expiration_data[:code_security_trial] = code_trial.expires_at if code_trial.trial_active?

      expiration_data
    end

    # Returns expiration information for active GHAS trials on the given entity,
    # merging in any active trials on the entity's billing business when applicable.
    sig { params(billable_entity: T.any(Business, Organization)).returns(T::Hash[Symbol, T.nilable(Date)]) }
    def self.active_ghas_trials_expiration(billable_entity:)
      expiration_data = T.let({}, T::Hash[Symbol, T.nilable(Date)])

      expiration_data.merge!(active_ghas_trials_data_for_entity(billable_entity: billable_entity))

      # If this is an organization with a billing entity (business), check trials on the business too
      if billable_entity.is_a?(Organization) && billable_entity.delegate_billing_to_business? && billable_entity.business.present?
        expiration_data.merge!(active_ghas_trials_data_for_entity(billable_entity: T.must(billable_entity.business)))
      end

      expiration_data
    end

    # Returns an array of active GHAS trial types on the given entity.
    sig { params(billable_entity: T.any(Business, Organization)).returns(T::Array[Symbol]) }
    def self.active_ghas_trials(billable_entity:)
      active_ghas_trials_expiration(billable_entity: billable_entity).keys
    end

    # Returns true if a SKU trial previously ran for the given entity and is no
    # longer active (i.e. an ended_at date is today or in the past).
    sig { params(billable_entity: T.any(Business, Organization)).returns(T::Boolean) }
    def self.advanced_security_free_trial_expired?(billable_entity:)
      return false if has_active_advanced_security_trial?(billable_entity: billable_entity)

      secret_trial = secret_protection_trial(billable_entity: billable_entity)
      code_trial = code_security_trial(billable_entity: billable_entity)

      [secret_trial.ended_at, code_trial.ended_at].compact.any? { |date| date <= GitHub::Billing.today }
    end

    # Returns the number of trial days a new trial would have if started today
    # for the given entity. Does not return the number of days left for an
    # active trial.
    sig { params(billable_entity: T.any(Business, Organization)).returns(Integer) }
    def self.new_advanced_security_trial_days(billable_entity:)
      return TRIAL_LENGTH_30 unless billable_entity.is_a?(Business)
      return billable_entity.trial_days_remaining || TRIAL_LENGTH_30 if billable_entity.trial?
      TRIAL_LENGTH_30
    end

    # Ends an active advanced security trial early. When `purchase_unbundled_trial`
    # is true the trial is converted to a paid subscription rather than churned.
    # StopTrialJob handles bulk disable + config cleanup based on reset_on_expiration flag:
    #  - For trial-to-paid: reset_on_expiration is set to false (keep services enabled)
    #  - For trial churn: reset_on_expiration stays true (disable services); the job runs
    #    sync to ensure usage is disabled before checkout.
    sig do
      params(
        billable_entity: T.any(Business, Organization),
        actor: User,
        is_stafftools_action: T::Boolean,
        purchase_unbundled_trial: T.nilable(T::Boolean),
      ).returns(GitHub::Result)
    end
    def self.end_advanced_security_trial(billable_entity:, actor:, is_stafftools_action: false, purchase_unbundled_trial: false)
      return GitHub::Result.error(AdvancedSecurity::Public::Subscription::UnprocessableError.new("GHAS is not currently enabled for organizations.")) if billable_entity.is_a?(Organization) && !billable_entity.feature_flag_enabled?(:ghas_self_serve_orgs, default: false)
      return GitHub::Result.error(AdvancedSecurity::Public::Subscription::UnprocessableError.new("Does not have active standalone trial to end")) if purchase_unbundled_trial && !has_active_advanced_security_trial?(billable_entity: billable_entity)

      billable_entity.set_customer_to_split_metered_offering(actor:) if purchase_unbundled_trial

      secret_protection_trial = secret_protection_trial(billable_entity: billable_entity)
      code_security_trial = code_security_trial(billable_entity: billable_entity)

      # Check if either trial is active
      secret_protection_trial_active = secret_protection_trial.trial_active?
      code_security_trial_active = code_security_trial.trial_active?

      result = T.let(nil, T.nilable(GitHub::Result))
      if !secret_protection_trial_active && !code_security_trial_active
        result = GitHub::Result.error(UnprocessableError.new("Cannot end trial when trial is not active."))
      else
        # When converting to paid, set reset_on_expiration to false to keep services enabled
        # When churning, leave reset_on_expiration as true (default) to bulk disable services
        if purchase_unbundled_trial
          secret_protection_trial.set_reset_on_expiration(actor: actor, reset_on_expiration: false) if secret_protection_trial_active
          code_security_trial.set_reset_on_expiration(actor: actor, reset_on_expiration: false) if code_security_trial_active
        end

        if secret_protection_trial_active
          if purchase_unbundled_trial
            StopTrialJob.perform_later(
              billable_entity: billable_entity,
              sku_name: EnterpriseCloudOnboard::SecretProtectionTrial::SKU_NAME
            )
          else # churning (disabling usage)
            begin
              StopTrialJob.perform_now(
                billable_entity: billable_entity,
                sku_name: EnterpriseCloudOnboard::SecretProtectionTrial::SKU_NAME
              )
            rescue StandardError => e
              GitHub.logger.error(
                "exception.message": "Failed to end Secret Protection trial: #{e.message}",
                "gh.user.id": actor.id,
                "gh.billable_entity.id": billable_entity.id,
                "gh.billable_entity.type": billable_entity.class.name
              )
              result = GitHub::Result.error(e)
            end
          end
        end

        if result.nil? && code_security_trial_active
          if purchase_unbundled_trial
            StopTrialJob.perform_later(
              billable_entity: billable_entity,
              sku_name: EnterpriseCloudOnboard::CodeSecurityTrial::SKU_NAME
            )
          else # churning (disabling usage)
            begin
              StopTrialJob.perform_now(
                billable_entity: billable_entity,
                sku_name: EnterpriseCloudOnboard::CodeSecurityTrial::SKU_NAME
              )
            rescue StandardError => e
              GitHub.logger.error(
                "exception.message": "Failed to end Code Security trial: #{e.message}",
                "gh.user.id": actor.id,
                "gh.billable_entity.id": billable_entity.id,
                "gh.billable_entity.type": billable_entity.class.name
              )
              result = GitHub::Result.error(e)
            end
          end
        end

        result ||= GitHub::Result.new { true }
      end

      event_suffix = is_stafftools_action ? "_in_stafftools" : ""
      instrument_advanced_security_event(
        billable_entity: billable_entity,
        result: result,
        event: "advanced_security_trial_ended_immediately#{event_suffix}"
      )
      result
    end

    # Extends active SKU trials by adding days to the current trial duration.
    # Used from stafftools to extend trials, capped at 60 days from today.
    sig do
      params(
        billable_entity: T.any(Business, Organization),
        actor: User,
        days: Integer,
        is_stafftools_action: T::Boolean,
      ).returns(GitHub::Result)
    end
    def self.extend_advanced_security_trial(billable_entity:, actor:, days:, is_stafftools_action: false)
      secret_protection_trial = secret_protection_trial(billable_entity: billable_entity)
      code_security_trial = code_security_trial(billable_entity: billable_entity)

      # Check if either trial is active
      secret_protection_trial_active = secret_protection_trial.trial_active?
      code_security_trial_active = code_security_trial.trial_active?

      result = if !secret_protection_trial_active && !code_security_trial_active
        GitHub::Result.error(UnprocessableError.new("Cannot extend trial when trial is not active."))
      else
        # Calculate the new trial duration (current duration + days to add)
        # Both trials should have the same duration, so use whichever is active
        current_trial = secret_protection_trial_active ? secret_protection_trial : code_security_trial
        current_duration = current_trial.number_of_days || 0
        new_duration = current_duration + days

        # Cap at 60 days from today (similar to legacy behavior)
        max_days_from_today = 60
        start_date = current_trial.started_at || Date.current
        days_since_start = (Date.current - start_date).to_i
        max_allowed_duration = days_since_start + max_days_from_today

        if new_duration > max_allowed_duration
          new_duration = max_allowed_duration
        end

        # Also cap at the SKU trial max (90 days)
        new_duration = [new_duration, EnterpriseCloudOnboard::SKUTrial::MAX_DAYS].min

        begin
          # Extend both active trials to the same duration
          if secret_protection_trial_active
            secret_protection_trial.set_number_of_days(actor: actor, days: new_duration)
          end
          if code_security_trial_active
            code_security_trial.set_number_of_days(actor: actor, days: new_duration)
          end

          # Calculate the new expiration date for the controller
          new_expires_at = (start_date + (new_duration + 1).days).to_date
          GitHub::Result.new { ExtendTrialResult.new(ends_on: new_expires_at) }
        rescue EnterpriseCloudOnboard::SKUTrial::InvalidNumberOfDays => e
          GitHub::Result.error(UnprocessableError.new("Invalid trial duration: #{e.message}"))
        rescue EnterpriseCloudOnboard::SKUTrial::WouldExpireError => e
          GitHub::Result.error(UnprocessableError.new("Cannot extend trial: #{e.message}"))
        end
      end

      instrument_advanced_security_event(
        billable_entity: billable_entity,
        result: result,
        event: "advanced_security_trial_extended_in_stafftools"
      )
      result
    end

    # Returns true if an account may start a self-serve advanced security trial.
    # If a caller has already checked for entity.potentially_trial_or_purchase_advanced_security?
    # then they may pass skip_shared_checks: true to skip those checks.
    sig do
      params(
        billable_entity: T.any(Business, Organization),
        skip_shared_checks: T::Boolean,
      ).returns(T::Boolean)
    end
    def self.eligible_for_self_serve_advanced_security_trial?(billable_entity:, skip_shared_checks: false)
      return false if !skip_shared_checks && !billable_entity.potentially_trial_or_purchase_advanced_security?
      return false if billable_entity.is_a?(Business) && !billable_entity.eligible_for_self_serve_payment?

      # Check eligibility for both Secret Protection and Code Security trials.
      # Both trials must be eligible (self-serve trials enable both SKUs together).
      secret_protection_trial(billable_entity: billable_entity).self_serve_eligibility_errors.empty? &&
        code_security_trial(billable_entity: billable_entity).self_serve_eligibility_errors.empty?
    end

    sig do
      params(
        billable_entity: T.any(Business, Organization),
        skip_shared_checks: T::Boolean,
      ).returns(T::Boolean)
    end
    def self.show_advanced_security_onboarding?(billable_entity:, skip_shared_checks: false)
      business = billable_entity.is_a?(Business) ? billable_entity : billable_entity.business
      return false unless business.present?
      return false if !skip_shared_checks && !business.potentially_trial_or_purchase_advanced_security?
      return false if business.has_self_serve_advanced_security? && !has_active_advanced_security_trial?(billable_entity: business)

      # Show onboarding only for active SKU trials (no post-trial experience)
      has_active_advanced_security_trial?(billable_entity: business)
    end

    sig { params(billable_entity: T.any(Business, Organization), trial_type: Symbol).returns(EnterpriseCloudOnboard::SecretProtectionTrial) }
    def self.secret_protection_trial(billable_entity:, trial_type: :ghas_stand_alone)
      EnterpriseCloudOnboard::SecretProtectionTrial.new(billable_entity: billable_entity, trial_type: trial_type)
    end

    sig { params(billable_entity: T.any(Business, Organization), trial_type: Symbol).returns(EnterpriseCloudOnboard::CodeSecurityTrial) }
    def self.code_security_trial(billable_entity:, trial_type: :ghas_stand_alone)
      EnterpriseCloudOnboard::CodeSecurityTrial.new(billable_entity: billable_entity, trial_type: trial_type)
    end

    sig do
      params(
        billable_entity: T.any(Business, Organization),
        result: GitHub::Result,
        event: T.any(String, Symbol),
        payload: T::Hash[Symbol, T.any(String, Symbol, Integer)],
      ).void
    end
    private_class_method def self.instrument_advanced_security_event(billable_entity:, result:, event:, payload: {})
      event_name = "#{T.must(billable_entity.class.name).downcase}.#{event}"
      datadog_tags = []
      payload.each do |key, value|
        # avoid datadog tags with high cardinality (many possible values)
        datadog_tags << "#{key}:#{value}" unless value.is_a?(Integer)
      end

      if result.ok?
        billable_entity.instrument(event, payload)
        GitHub.dogstats.increment(event_name, tags: datadog_tags)
      else
        error_event_name = "#{event_name}.error"
        # GitHub::Result.error does not enforce types, so check for a string type.
        error = result.error.is_a?(String) ? AdvancedSecurity::Public::Subscription::UnprocessableError.new(result.error) : result.error
        Failbot.report(
          error,
          catalog_service: "github/ghas_self_serve_trial",
          account_id: billable_entity.id,
          account_type: T.must(billable_entity.class.name),
          failed_event: event_name,
          event_payload: payload,
        )
        GitHub.dogstats.increment(error_event_name, tags: datadog_tags)
      end
      # note that we also instrument the "analytics.event" hydro event in related controllers
    end
  end
end
