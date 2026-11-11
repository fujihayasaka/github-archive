# typed: strict
# frozen_string_literal: true

module AdvancedSecurity
  module Public
    # Public: The public Subscription module for Advanced Security Subscriptions.
    #   This module will enable the creation of advanced security products for an Organization or Business.
    #   This module is included in the User and Business models, but can only be used by Organizations and Businesses.
    #
    module Subscription
      extend T::Helpers
      include GitHub::ResilienceMixin

      class UnprocessableError < StandardError; end

      TRIAL_LENGTH_14 = T.let(14, Integer)
      TRIAL_LENGTH_30 = T.let(30, Integer)

      ADVANCED_SECURITY_MONTHLY_PRODUCT = T.let(
        Billing::Public::Product::ProductIdentifier.new(
          product_type: "github.advanced_security",
          product_key: "v0",
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month
        ).freeze,
        Billing::Public::Product::ProductIdentifier
      )

      ## This product has not yet been created in Zuora, and should not be actively used without a feature flag.
      ## See https://github.com/github/gitcoin/issues/9506 for more information.
      ADVANCED_SECURITY_YEARLY_PRODUCT = T.let(
        Billing::Public::Product::ProductIdentifier.new(
          product_type: "github.advanced_security",
          product_key: "v0",
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Year
        ).freeze,
        Billing::Public::Product::ProductIdentifier
      )

      sig do
        params(
          actor: User,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle,
          is_stafftools_action: T::Boolean,
          volume_unbundled_trial: T::Boolean,
          trial_source: Symbol
        ).returns(GitHub::Result)
      end
      def subscribe_to_advanced_security_trial(actor:, billing_cycle:, is_stafftools_action: false, volume_unbundled_trial: false, trial_source: :legacy_ghas_self_serve)
        T.bind(self, T.any(Organization, Business))

        return GitHub::Result.error(UnprocessableError.new("Yearly GHAS subscriptions are not yet available.")) if billing_cycle == Billing::Public::SubscriptionItems::BillingCycle::Year && !self.feature_flag_enabled_or_raise?(:ghas_self_serve_post_mvp) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        return GitHub::Result.error(UnprocessableError.new("GHAS is not currently enabled for organizations.")) if organization? && !self.feature_flag_enabled_or_raise?(:ghas_self_serve_orgs) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        return GitHub::Result.error(UnprocessableError.new("Metered plans cannot add subscription items.")) unless metered_ghe_allow_ghas_trial?

        product = product_identifier(billing_cycle: billing_cycle)
        trial_days = self.new_advanced_security_trial_days
        dual_enterprise_trial = self.is_a?(Business) && self.trial?
        result = self.subscribe_to_product(
          product,

          # We set this to one, but during an active trial a business will have unlimited seats.
          # See AdvancedSecurityLicense#unlimited_seats?
          quantity: 1,
          actor: actor,
          free_trial_length: trial_days.days,
          is_stafftools_action: is_stafftools_action,
        )

        # for cancellation cleanup see config/instrumentation/advanced_security.rb
        if result.ok? && has_active_advanced_security_subscription?
          if volume_unbundled_trial
            self.mark_advanced_security_as_purchased_for_entity_as_volume_unbundled(actor: actor, is_stafftools_action: is_stafftools_action)
          else
            self.mark_advanced_security_as_purchased_for_entity(actor: actor, is_stafftools_action: is_stafftools_action)
          end

          start_method = case trial_source
          when :digital_front_door
            :DFD
          when :ghas_stand_alone
            :SELF_SERVE
          else
            :LEGACY_SELF_SERVE_VOLUME
          end
          message = {
            enterprise_id: self.is_a?(Business) ? self.id : nil,
            organization_id: self.is_a?(Organization) ? self.id : nil,
            action: :STARTED,
            trial_sku: :ADVANCED_SECURITY,
            start_method: start_method,
          }
          GlobalInstrumenter.instrument("advanced_security_trial.toggled", message)
        end
        if volume_unbundled_trial && self.is_a?(Business)
          # Set GitHub Recommended configuration as default
          github_config = SecurityConfiguration.github_recommended_configuration
          if github_config
            SecurityConfigurationDefault.create_or_update_defaults(
              target: self,
              security_configuration: github_config,
              default_for_new_public_repos: true,
              default_for_new_private_repos: false
            )

            # Apply GitHub Recommended configuration to existing repos without any configuration
            EnterpriseCloudOnboard::AdvancedSecurityTrial.apply_github_recommended_to_unattached_repos(
              self,
              github_config,
              actor
            )
          end
        end
        instrument_advanced_security_event(result: result, event: "advanced_security_trial_created", payload: {
          trial_days: trial_days,
          dual_enterprise_trial: dual_enterprise_trial,
        })
        result
        # If we choose to customize our email sends, we'd enqueue a job here.
      end

      sig do
        params(
          seats: Integer,
          actor: User,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle,
          is_stafftools_action: T::Boolean,
          skip_sync: T::Boolean,
        ).returns(GitHub::Result)
      end
      def subscribe_to_advanced_security(seats:, actor:, billing_cycle:, is_stafftools_action: false, skip_sync: false)
        T.bind(self, T.any(Organization, Business))
        return GitHub::Result.error(UnprocessableError.new("Yearly GHAS subscriptions are not yet available.")) if billing_cycle == Billing::Public::SubscriptionItems::BillingCycle::Year && !self.feature_flag_enabled_or_raise?(:ghas_self_serve_post_mvp) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        return GitHub::Result.error(UnprocessableError.new("GHAS is not currently enabled for organizations.")) if organization? && !self.feature_flag_enabled_or_raise?(:ghas_self_serve_orgs) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        return GitHub::Result.error(UnprocessableError.new("Metered plans cannot add subscription items.")) unless metered_ghe_allow_ghas_trial?
        product = product_identifier(billing_cycle: billing_cycle)

        if has_active_advanced_security_trial?
          convert_trial_result = Billing::Public::SubscriptionItem.end_free_trial_now!(
            actor: actor,
            product: product,
            account: self,
            purchase_subscription: true,
            seats: seats,
            skip_sync: skip_sync,
          )

          if convert_trial_result.ok?
            message = {
              enterprise_id: self.is_a?(Business) ? self.id : nil,
              organization_id: self.is_a?(Organization) ? self.id : nil,
              action: :ENDED,
              trial_sku: :ADVANCED_SECURITY,
              converted_to_paid: true,
              **self.advanced_security_usage_stats
            }
            GlobalInstrumenter.instrument("advanced_security_trial.toggled", message)
          end

          instrument_advanced_security_event(result: convert_trial_result, event: "advanced_security_subscribed", payload: {
            converted_from_trial: true,
            seats: seats,
            skip_sync: skip_sync,
          })
          return convert_trial_result
        end

        result = self.subscribe_to_product(product, quantity: seats, actor: actor, is_stafftools_action: is_stafftools_action, skip_sync: skip_sync)

        # Since it's possible for payment to be collected synchronously in the background,
        # there could be a race condition between marking advanced security as not purchased
        # and marking it as purchased. To avoid this, we'll only mark advanced security as purchased
        # if the subscription is still active and thus hasn't been cancelled.
        if result.ok? && has_active_advanced_security_subscription?
          self.mark_advanced_security_as_purchased_for_entity(actor: actor, is_stafftools_action: is_stafftools_action)
        end

        instrument_advanced_security_event(result: result, event: "advanced_security_subscribed", payload: {
          converted_from_trial: false,
          seats: seats,
          skip_sync: skip_sync,
        })

        result
      end

      # This is used in Stafftools to extend a trial, up to 60 days from today
      sig do
        params(
          actor: User,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle,
          days: Integer,
          is_stafftools_action: T::Boolean,
        ).returns(GitHub::Result)
      end
      def extend_advanced_security_trial(actor:, billing_cycle:, days:, is_stafftools_action: false)
        T.bind(self, T.any(Organization, Business))
        return GitHub::Result.error(UnprocessableError.new("Yearly GHAS subscriptions are not yet available.")) if billing_cycle == Billing::Public::SubscriptionItems::BillingCycle::Year && !self.feature_flag_enabled_or_raise?(:ghas_self_serve_post_mvp) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        return GitHub::Result.error(UnprocessableError.new("GHAS is not currently enabled for organizations.")) if organization? && !self.feature_flag_enabled_or_raise?(:ghas_self_serve_orgs) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        return GitHub::Result.error(UnprocessableError.new("Metered plans cannot add subscription items.")) unless metered_ghe_allow_ghas_trial?

        product = product_identifier(billing_cycle: billing_cycle)
        result = Billing::Public::SubscriptionItem.extend_trial!(
          actor: actor,
          product: product,
          account: self,
          days: days,
          is_stafftools_action: is_stafftools_action,
        )
        instrument_advanced_security_event(result: result, event: "advanced_security_trial_extended_in_stafftools")
        result
      end

      # This is used in Stafftools to end trials early
      sig do
        params(
          actor: User,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle,
          is_stafftools_action: T::Boolean,
          purchase_unbundled_trial: T.nilable(T::Boolean),

        ).returns(GitHub::Result)
      end
      def end_advanced_security_trial(actor:, billing_cycle:, is_stafftools_action: false, purchase_unbundled_trial: false)
        T.bind(self, T.any(Organization, Business))
        return GitHub::Result.error(UnprocessableError.new("Yearly GHAS subscriptions are not yet available.")) if billing_cycle == Billing::Public::SubscriptionItems::BillingCycle::Year && !self.feature_flag_enabled?(:ghas_self_serve_post_mvp, default: false)
        return GitHub::Result.error(UnprocessableError.new("GHAS is not currently enabled for organizations.")) if organization? && !self.feature_flag_enabled?(:ghas_self_serve_orgs, default: false)
        return GitHub::Result.error(UnprocessableError.new("Does not have active standalone trial to end")) if purchase_unbundled_trial && !has_active_standalone_unbundled_advanced_security_trial?

        if purchase_unbundled_trial
          # once we set this, `has_active_standalone_unbundled_advanced_security_trial?` will return false!
          self.set_customer_to_split_metered_offering(actor:)
        end

        result = GitHub::Result.new { nil }
        has_sku_trial = FeatureFlag.vexi.enabled?(:unified_self_serve_ghas_trials, self, default: false) &&
          EnterpriseCloudOnboard::AdvancedSecurityTrial.has_active_advanced_security_trial?(billable_entity: self)

        # End SKU-based trials if they exist
        if has_sku_trial
          result = EnterpriseCloudOnboard::AdvancedSecurityTrial.end_sku_trials_if_active(
            billable_entity: self,
            actor: actor,
            converting_to_paid: !!purchase_unbundled_trial
          )
        else
          product = product_identifier(billing_cycle: billing_cycle)
          result = Billing::Public::SubscriptionItem.end_free_trial_now!(
            actor: actor,
            product: product,
            account: self,
            purchase_subscription: false,
            is_stafftools_action: is_stafftools_action,
          )
        end

        # We only need to do when purchasing, otherwise we will do so when
        # the subscription cancellation is processed.
        # Note: For SKU trials, StopTrialJob publishes separate events for each SKU (CODE_SECURITY, SECRET_PROTECTION)
        # so we don't publish the aggregate ADVANCED_SECURITY event to avoid duplication
        if result.ok? && purchase_unbundled_trial && !has_sku_trial
          message = {
            enterprise_id: self.is_a?(Business) ? self.id : nil,
            organization_id: self.is_a?(Organization) ? self.id : nil,
            action: :ENDED,
            trial_sku: :ADVANCED_SECURITY,
            converted_to_paid: true,
            **self.advanced_security_usage_stats
          }
          GlobalInstrumenter.instrument("advanced_security_trial.toggled", message)
        end

        event_suffix = is_stafftools_action ? "_in_stafftools" : ""
        instrument_advanced_security_event(result: result, event: "advanced_security_trial_ended_immediately#{event_suffix}")
        result
      end

      sig do
        params(
          actor: User,
          force: T::Boolean,
          skip_sync: T::Boolean
        ).returns(GitHub::Result)
      end
      def cancel_advanced_security_subscription(actor:, force: false, skip_sync: false)
        T.bind(self, T.any(Organization, Business))
        return GitHub::Result.error(UnprocessableError.new("GHAS is not currently enabled for organizations.")) if organization? && !self.feature_flag_enabled_or_raise?(:ghas_self_serve_orgs) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

        result = GitHub::Result.error(UnprocessableError.new("No active GHAS subscription found."))

        if has_active_monthly_advanced_security_subscription?
          result = self.cancel_product_subscription(ADVANCED_SECURITY_MONTHLY_PRODUCT, actor: actor, force: force, skip_sync: skip_sync)
        elsif self.feature_flag_enabled_or_raise?(:ghas_self_serve_post_mvp) && has_active_yearly_advanced_security_subscription? # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          result = self.cancel_product_subscription(ADVANCED_SECURITY_YEARLY_PRODUCT, actor: actor, force: force, skip_sync: skip_sync)
        end

        event = force ? "advanced_security_cancelled" : "advanced_security_cancellation_scheduled"
        instrument_advanced_security_event(result: result, event: event)

        result
      end

      sig { returns(T::Boolean) }
      def has_active_advanced_security_subscription?
        T.bind(self, T.any(Organization, Business))

        has_active_monthly_advanced_security_subscription? || has_active_yearly_advanced_security_subscription?
      end

      sig { returns(T::Boolean) }
      def has_active_yearly_advanced_security_subscription?
        T.bind(self, T.any(Organization, Business))

        self.subscribed_to_product?(ADVANCED_SECURITY_YEARLY_PRODUCT)
      end

      sig { returns(T::Boolean) }
      def has_active_monthly_advanced_security_subscription?
        T.bind(self, T.any(Organization, Business))

        self.subscribed_to_product?(ADVANCED_SECURITY_MONTHLY_PRODUCT)
      end

      sig { returns(T::Boolean) }
      def has_active_advanced_security_trial?
        T.bind(self, T.any(Organization, Business))
        # Check new SKU-based trials first if FF enabled
        if FeatureFlag.vexi.enabled?(:unified_self_serve_ghas_trials, self, default: false)
          return true if EnterpriseCloudOnboard::AdvancedSecurityTrial.has_active_advanced_security_trial?(billable_entity: self)
        end
        # Fall back to legacy subscription item trial
        advanced_security = self.advanced_security_subscription_item
        return false unless advanced_security
        advanced_security.on_free_trial?
      end

      # This can be removed when the Azure payment options are addressed for checkout
      sig { returns(T::Boolean) }
      def has_active_standalone_unbundled_advanced_security_trial?
        T.bind(self, T.any(Organization, Business))
        return false unless self.is_a?(Business)
        return false unless self.advanced_security_subscription_item&.on_free_trial?
        return false if self.dfd_trial?

        self.advanced_security_enabled_type_for_entity == Configurable::AdvancedSecurityBillingConfig::SPLIT_VOLUME
      end

      # This is only used when a trial churns and we need to reset GHAS
      sig { returns(T::Boolean) }
      def had_active_standalone_unbundled_advanced_security_trial?
        T.bind(self, T.any(Organization, Business))
        return false unless self.is_a?(Business)
        return false if self.dfd_trial?

        self.advanced_security_enabled_type_for_entity == Configurable::AdvancedSecurityBillingConfig::SPLIT_VOLUME
      end

      sig { returns(T.nilable(Date)) }
      def advanced_security_free_trial_ends_on
        T.bind(self, T.any(Organization, Business))

        # Check new SKU-based trials first if FF enabled
        if FeatureFlag.vexi.enabled?(:unified_self_serve_ghas_trials, self, default: false)
          expires_at = EnterpriseCloudOnboard::AdvancedSecurityTrial.advanced_security_free_trial_ends_on(billable_entity: self)
          return expires_at if expires_at.present?
        end

        # Fall back to legacy subscription item trial
        advanced_security = self.advanced_security_subscription_item
        return unless advanced_security
        advanced_security.free_trial_ends_on
      end

      sig { returns(T::Boolean) }
      def advanced_security_free_trial_expired?
        T.bind(self, T.any(Organization, Business))

        # Check new SKU-based trials first if FF enabled
        if FeatureFlag.vexi.enabled?(:unified_self_serve_ghas_trials, self, default: false)
          expires_at = EnterpriseCloudOnboard::AdvancedSecurityTrial.advanced_security_free_trial_ends_on(billable_entity: self)
          return expires_at < Date.current if expires_at.present?
        end

        # Fall back to legacy subscription item trial
        advanced_security = self.advanced_security_subscription_item
        return false unless advanced_security
        advanced_security.free_trial_expired?
      end

      # Returns an array of active GHAS trial types
      sig { returns(T::Array[Symbol]) }
      def active_ghas_trials
        T.bind(self, T.any(Organization, Business))
        active_ghas_trials_expiration.keys
      end

      # Returns expiration information for active GHAS trials
      sig { returns(T::Hash[Symbol, T.nilable(Date)]) }
      def active_ghas_trials_expiration
        T.bind(self, T.any(Organization, Business))

        expiration_data = T.let({}, T::Hash[Symbol, T.nilable(Date)])

        # Check trials on this entity
        expiration_data.merge!(active_ghas_trials_data_for_entity(self))

        # If this is an organization with a billing entity (business), check trials on the business too
        if self.is_a?(Organization) && self.delegate_billing_to_business? && self.business.present?
          expiration_data.merge!(active_ghas_trials_data_for_entity(T.must(self.business)))
        end

        expiration_data
      end

      # Returns trial data for a specific entity (Organization or Business)
      sig { params(entity: T.any(Organization, Business)).returns(T::Hash[Symbol, T.nilable(Date)]) }
      def active_ghas_trials_data_for_entity(entity)
        expiration_data = T.let({}, T::Hash[Symbol, T.nilable(Date)])

        # Check new SKU-based trials first if FF enabled
        if FeatureFlag.vexi.enabled?(:unified_self_serve_ghas_trials, entity, default: false)
          expiration_data = EnterpriseCloudOnboard::AdvancedSecurityTrial.active_ghas_trials_data_for_entity(billable_entity: entity)
          # If we found SKU trials, return them; otherwise fall through to legacy check
          return expiration_data if expiration_data.present?
        end

        # Fall back to legacy subscription-based trials
        # DFD self-serve trial or GHAS standalone trial (Business only)
        if entity.has_active_advanced_security_trial? && entity.is_a?(Business)
          trial_type = entity.dfd_trial? ? :dfd_self_serve_trial : :ghas_stand_alone_trial
          expiration_data[trial_type] = entity.advanced_security_free_trial_ends_on
          return expiration_data
        end

        expiration_data
      end

      sig { returns(T.nilable(Billing::Public::SubscriptionItem)) }
      def advanced_security_subscription_item
        T.bind(self, T.any(Organization, Business))

        monthly_advanced_security_subscription_item || yearly_advanced_security_subscription_item
      end

      sig { returns(T.nilable(Billing::Public::SubscriptionItem)) }
      def monthly_advanced_security_subscription_item
        T.bind(self, T.any(Organization, Business))

        Billing::Public::SubscriptionItem.all_active(
          product: ::AdvancedSecurity::Public::Subscription::ADVANCED_SECURITY_MONTHLY_PRODUCT,
          account: self,
        ).value { [] }.first
      end

      sig { returns(T.nilable(Billing::Public::SubscriptionItem)) }
      def yearly_advanced_security_subscription_item
        T.bind(self, T.any(Organization, Business))

        Billing::Public::SubscriptionItem.all_active(
          product: ::AdvancedSecurity::Public::Subscription::ADVANCED_SECURITY_YEARLY_PRODUCT,
          account: self,
        ).value { [] }.first
      end

      sig { returns(T::Boolean) }
      def advanced_security_subscription_cancellation_pending?
        T.bind(self, T.any(Organization, Business))
        pending_subscription_item_changes.cancellation.for_product_uuid_subscribable(ADVANCED_SECURITY_MONTHLY_PRODUCT).exists?
      end

      sig { returns(T::Boolean) }
      def advanced_security_subscription_seat_changes_pending?
        T.bind(self, T.any(Organization, Business))
        pending_subscription_item_changes.cancellation.invert_where.for_product_uuid_subscribable(ADVANCED_SECURITY_MONTHLY_PRODUCT).exists?
      end

      sig { returns(T.nilable(Billing::PendingSubscriptionItemChange)) }
      def advanced_security_subscription_change
        T.bind(self, T.any(Organization, Business))
        pending_subscription_item_changes.for_product_uuid_subscribable(ADVANCED_SECURITY_MONTHLY_PRODUCT).last
      end

      # Shared checks between purchasing advanced security and advanced security trial
      # Purchasing requires an additional !enterprise.trial? check
      # Trial needs to verify that a past trial has not occurred
      sig { returns(T::Boolean) }
      def potentially_trial_or_purchase_advanced_security?
        T.bind(self, T.any(Organization, Business))
        with_error_fallback(fallback: false, allowed_error_types: DATABASE_ERROR_TYPES_ALLOWLIST + [Faraday::TimeoutError, Zuorest::TooManyRequestsError]) do
          return false if GitHub.enterprise?
          return false unless self.is_a?(Business)
          return false if downgraded_to_free_plan?
          # the rules differ between self-serve and sales-managed
          if eligible_for_self_serve_payment?
            return false unless metered_ghe_allow_ghas_trial?
            return false if self.dunning?
          else
            return false unless self.sales_managed_subscription_self_serve_eligible?
            return false unless self.billing_term_ends_on
            return false unless self.billing_term_ends_on > (GitHub::Billing.today - 1.year)
            return false if self.past_due_invoice?
          end
          true
        end.value
      end

      # Public: Returns true if an account may purchase self-serve advanced security.
      # If a caller has already checked for entity.potentially_trial_or_purchase_advanced_security?
      # then they may pass skip_shared_checks: true to skip those checks.
      sig { params(skip_shared_checks: T::Boolean).returns(T::Boolean) }
      def eligible_for_self_serve_advanced_security?(skip_shared_checks: false)
        T.bind(self, T.any(Organization, Business))
        return false if !skip_shared_checks && !self.potentially_trial_or_purchase_advanced_security?
        return false unless self.is_a?(Business)
        return false if self.trial?
        true
      end

      # Public: Returns true if an account may start a self-serve advanced security.
      # If a caller has already checked for entity.potentially_trial_or_purchase_advanced_security?
      # then they may pass skip_shared_checks: true to skip those checks.
      sig { params(skip_shared_checks: T::Boolean).returns(T::Boolean) }
      def eligible_for_self_serve_advanced_security_trial?(skip_shared_checks: false)
        T.bind(self, T.any(Organization, Business))
        return false if !skip_shared_checks && !self.potentially_trial_or_purchase_advanced_security?

        if self.is_a?(Business) && !eligible_for_self_serve_payment?
          false
        else
          return false if self.advanced_security_metered_for_entity? # prevent self-serve trials for metered GHAS
          return false if self.new_advanced_security_trial_days < TRIAL_LENGTH_14

          # Check new SKU-based trial eligibility first if FF enabled
          if FeatureFlag.vexi.enabled?(:unified_self_serve_ghas_trials, self, default: false)
            # Check eligibility for both Secret Protection and Code Security trials
            secret_protection_trial = EnterpriseCloudOnboard::SecretProtectionTrial.new(billable_entity: self)
            code_security_trial = EnterpriseCloudOnboard::CodeSecurityTrial.new(billable_entity: self)

            # Both trials must be eligible (self-serve trials enable both SKUs together)
            secret_protection_eligible = secret_protection_trial.self_serve_eligibility_errors.empty?
            code_security_eligible = code_security_trial.self_serve_eligibility_errors.empty?

            return secret_protection_eligible && code_security_eligible
          end

          # Fall back to legacy subscription_item eligibility check
          ::Billing::Public::SubscriptionItem.eligible_for_free_trial?(
            product: ::AdvancedSecurity::Public::Subscription::ADVANCED_SECURITY_MONTHLY_PRODUCT,
            account: self,
          )
        end
      end

      sig { params(skip_shared_checks: T::Boolean).returns(T::Boolean) }
      def show_advanced_security_onboarding?(skip_shared_checks: false)
        T.bind(self, T.any(Organization, Business))
        business = self.is_a?(Business) ? self : self.business
        return false unless business.present?
        return false if !skip_shared_checks && !business.potentially_trial_or_purchase_advanced_security?
        return false if business.has_self_serve_advanced_security? && !business.has_active_advanced_security_trial?

        # Check new SKU-based trials first if FF enabled
        if FeatureFlag.vexi.enabled?(:unified_self_serve_ghas_trials, business, default: false)
          # Show onboarding if there's an active SKU trial or one that ended recently (within trial length + 7 days)
          if EnterpriseCloudOnboard::AdvancedSecurityTrial.has_active_advanced_security_trial?(billable_entity: business)
            return true
          end

          # Also check for recently ended SKU trials (for post-trial onboarding experience)
          ended_at = EnterpriseCloudOnboard::AdvancedSecurityTrial.trial_ended_at(billable_entity: business)
          if ended_at.present?
            days_since_ended = T.unsafe(Date.current - ended_at).to_i
            return true if days_since_ended <= (TRIAL_LENGTH_30 + 7)
          end

          # No SKU trial found, return false when FF is enabled
          return false
        end

        # Fall back to legacy subscription_items trial check
        Billing::Public::SubscriptionItem.trial_exists?(
          product: ::AdvancedSecurity::Public::Subscription::ADVANCED_SECURITY_MONTHLY_PRODUCT,
          account: business,
          within: (TRIAL_LENGTH_30 + 7 + 1).days.ago # Trial Length + 7 days + 1 for bounds
        ).value { false }
      end

      sig { params(actor: User).returns(T.nilable(Organization)) }
      def organization_for_advanced_security_trial(actor:)
        T.bind(self, T.any(Organization, Business))
        case self
        when Organization
          self
        when Business
          self.filtered_organizations(viewer: actor, viewer_role: "owner").first
        else
          T.absurd(self)
        end
      end

      sig { returns(T::Boolean) }
      def never_billed_for_self_serve_advanced_security?
        T.bind(self, T.any(Organization, Business))
        if organization?
          return Billing::BillingTransaction::LineItem.for_user(self.id).advanced_security.paid.count.zero?
        end
        Billing::BillingTransaction::LineItem.for_business(self).advanced_security.paid.count.zero?
      end

      # Public: Returns number of trials days if we were to start a new trial today.
      # Does not return the number of days left for an active trial.
      sig { returns(Integer) }
      def new_advanced_security_trial_days
        T.bind(self, T.any(Organization, Business))
        return TRIAL_LENGTH_30 unless self.is_a?(Business)
        return self.trial_days_remaining || TRIAL_LENGTH_30 if self.trial?
        TRIAL_LENGTH_30
      end

      private

      sig do
        params(billing_cycle: Billing::Public::SubscriptionItems::BillingCycle).returns(Billing::Public::Product::ProductIdentifier)
      end
      def product_identifier(billing_cycle:)
        T.bind(self, T.any(Organization, Business))
        return ADVANCED_SECURITY_YEARLY_PRODUCT if billing_cycle == Billing::Public::SubscriptionItems::BillingCycle::Year && self.feature_flag_enabled_or_raise?(:ghas_self_serve_post_mvp) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        ADVANCED_SECURITY_MONTHLY_PRODUCT
      end

      sig do
        params(
          result: GitHub::Result,
          event: T.any(String, Symbol),
          payload: T::Hash[Symbol, T.any(String, Symbol, Integer)],
        ).void
      end
      def instrument_advanced_security_event(result:, event:, payload: {})
        T.bind(self, T.any(Organization, Business))
        event_name = "#{T.must(self.class.name).downcase}.#{event}"
        datadog_tags = []
        payload.each do |key, value|
          # avoid datadog tags with high cardinality (many possible values)
          datadog_tags << "#{key}:#{value}" unless value.is_a?(Integer)
        end

        if result.ok?
          instrument event, payload
          GitHub.dogstats.increment(event_name, tags: datadog_tags)
        else
          error_event_name = "#{event_name}.error"
          # GitHub::Result.error does not enforce types, so check for a string type.
          error = result.error.is_a?(String) ? UnprocessableError.new(result.error) : result.error
          Failbot.report(
            error,
            catalog_service: "github/ghas_self_serve_trial",
            account_id: self.id,
            account_type: T.must(self.class.name),
            failed_event: event_name,
            event_payload: payload,
          )
          GitHub.dogstats.increment(error_event_name, tags: datadog_tags)
        end
        # note that we also instrument the "analytics.event" hydro event in related controllers
      end

      # Private: Temporary method to provide a single location to turn off advanced security for metered accounts.
      # Currently, metered GHE trials are eligible for advanced security, but converted metered GHE accounts are not.
      sig { returns(T::Boolean) }
      def metered_ghe_allow_ghas_trial?
        T.bind(self, T.any(Organization, Business))

        return true unless self.is_a?(Business)
        return true unless self.metered_ghe?

        self.trial?
      end
    end
  end
end
