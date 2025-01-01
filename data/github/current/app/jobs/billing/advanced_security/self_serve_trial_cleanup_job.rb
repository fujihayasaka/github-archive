# typed: strict
# frozen_string_literal: true

module Billing
  module AdvancedSecurity
    class SelfServeTrialCleanupJob < ApplicationJob
      extend T::Sig
      class ExpiryError < StandardError; end

      queue_as :ghas_trial

      retry_on ActiveJob::DeserializationError
      retry_on_dirty_exit
      retry_on_recoverable_exceptions

      sig { params(subscription_item: ::Billing::SubscriptionItem).void }
      def perform(subscription_item)
        return unless GitHub.billing_enabled?
        return unless subscription_item.present?

        business = subscription_item.account
        return unless business.present? && business.is_a?(Business)
        # If a cancellation is pending let that run
        return if subscription_item.pending_cancellation?

        business_id = business.id
        business_slug = business.slug
        class_name = self.class.name
        subscription_item_id = subscription_item.id

        GitHub.logger.info(
          "Job started",
          "gh.business.id": business_id,
          "gh.business.slug": business_slug,
          "code.namespace": class_name,
          "code.function": __method__,
        )

        result = "trial expired cleanly"

        has_access_to_advanced_security = business.advanced_security_purchased_for_entity?
        # This includes any failed attempts. Allow customer to go into dunning if they attempted to purchase.
        never_billed = business.never_billed_for_self_serve_advanced_security?

        if has_access_to_advanced_security && never_billed
          result = "detected a potentially bad trial expiry"
          GitHub.dogstats.increment("business.advanced_security_trial_bad_expiry")
          Failbot.report(
            ExpiryError.new("Detected an advanced security trial that did not expire correctly. Please confirm in" \
              " enterprise stafftools, if payment was attempted or was manually converted incorrectly. The subscription" \
              " item may be manually cancelled in enterprise stafftools."),
            catalog_service: "github/ghas_self_serve_trial",
            business_id: business_id,
            business_slug: business_slug,
            subscription_item_id: subscription_item_id
          )
        end

        GitHub.logger.info(
          "Job ended",
          "gh.business.id": business_id,
          "gh.business.slug": business_slug,
          "code.namespace": class_name,
          "code.function": __method__,
          "gh.ghas_trial_cleanup.result": result
        )
      end
    end
  end
end
