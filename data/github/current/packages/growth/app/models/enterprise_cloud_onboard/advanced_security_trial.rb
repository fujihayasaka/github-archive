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
      expires_at = advanced_security_free_trial_ends_on(billable_entity: billable_entity)
      return nil if expires_at.nil?

      # Date subtraction returns Rational, but Sorbet's stdlib types it as Date
      T.unsafe(expires_at - Date.current).to_i
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

    sig { params(billable_entity: T.any(Business, Organization), actor: User, converting_to_paid: T::Boolean).returns(GitHub::Result) }
    def self.end_sku_trials_if_active(billable_entity:, actor:, converting_to_paid: false)
      secret_protection_trial = secret_protection_trial(billable_entity: billable_entity)
      code_security_trial = code_security_trial(billable_entity: billable_entity)

      # Check if either trial is active
      secret_protection_trial_active = secret_protection_trial.trial_active?
      code_security_trial_active = code_security_trial.trial_active?
      return GitHub::Result.error(UnprocessableError.new("Cannot end trial when trial is not active.")) unless secret_protection_trial_active || code_security_trial_active

      # When converting to paid, set reset_on_expiration to false to keep services enabled
      # When churning, leave reset_on_expiration as true (default) to bulk disable services
      if converting_to_paid
        secret_protection_trial.set_reset_on_expiration(actor: actor, reset_on_expiration: false) if secret_protection_trial_active
        code_security_trial.set_reset_on_expiration(actor: actor, reset_on_expiration: false) if code_security_trial_active
      end

      # End both trials if they are active
      # StopTrialJob handles bulk disable + config cleanup based on reset_on_expiration flag
      # For trial-to-paid: reset_on_expiration should be false (keep services enabled)
      # For trial churn: reset_on_expiration should be true (disable services), should be run sync to ensure usage is disabled before checkout
      if secret_protection_trial_active
        if converting_to_paid
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
            return GitHub::Result.error(e)
          end
        end
      end

      if code_security_trial_active
        if converting_to_paid
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
            return GitHub::Result.error(e)
          end
        end
      end

      GitHub::Result.new { true }
    end

    # Extends active SKU trials by adding days to the current trial duration
    # This is used from stafftools to extend trials, capped at 60 days from today
    sig { params(billable_entity: T.any(Business, Organization), actor: User, days: Integer).returns(GitHub::Result) }
    def self.extend_sku_trials(billable_entity:, actor:, days:)
      secret_protection_trial = secret_protection_trial(billable_entity: billable_entity)
      code_security_trial = code_security_trial(billable_entity: billable_entity)

      # Check if either trial is active
      secret_protection_trial_active = secret_protection_trial.trial_active?
      code_security_trial_active = code_security_trial.trial_active?
      return GitHub::Result.error(UnprocessableError.new("Cannot extend trial when trial is not active.")) unless secret_protection_trial_active || code_security_trial_active

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
        new_expires_at = (start_date + new_duration.days).to_date
        GitHub::Result.new { ExtendTrialResult.new(ends_on: new_expires_at) }
      rescue EnterpriseCloudOnboard::SKUTrial::InvalidNumberOfDays => e
        GitHub::Result.error(UnprocessableError.new("Invalid trial duration: #{e.message}"))
      rescue EnterpriseCloudOnboard::SKUTrial::WouldExpireError => e
        GitHub::Result.error(UnprocessableError.new("Cannot extend trial: #{e.message}"))
      end
    end

    sig { params(billable_entity: T.any(Business, Organization), trial_type: Symbol).returns(EnterpriseCloudOnboard::SecretProtectionTrial) }
    def self.secret_protection_trial(billable_entity:, trial_type: :ghas_stand_alone)
      EnterpriseCloudOnboard::SecretProtectionTrial.new(billable_entity: billable_entity, trial_type: trial_type)
    end

    sig { params(billable_entity: T.any(Business, Organization), trial_type: Symbol).returns(EnterpriseCloudOnboard::CodeSecurityTrial) }
    def self.code_security_trial(billable_entity:, trial_type: :ghas_stand_alone)
      EnterpriseCloudOnboard::CodeSecurityTrial.new(billable_entity: billable_entity, trial_type: trial_type)
    end
  end
end
