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

        # GHAS trials are no longer backed by subscription items, so calling
        # subscribe_to_product during an active SKU trial would create a paid
        # subscription alongside the trial. Conversion must go through
        # #end_advanced_security_trial first; here we no-op rather than error
        # to preserve existing call-site behavior.
        return GitHub::Result.new { self } if has_active_advanced_security_trial?

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

      sig { returns(T::Boolean) }
      def never_billed_for_self_serve_advanced_security?
        T.bind(self, T.any(Organization, Business))
        if organization?
          return Billing::BillingTransaction::LineItem.for_user(self.id).advanced_security.paid.count.zero?
        end
        Billing::BillingTransaction::LineItem.for_business(self).advanced_security.paid.count.zero?
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
