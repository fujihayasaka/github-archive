# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

module Billing
  module AdvancedSecurity
    class SelfServeTrialCleanupSearchJob < BatchedJob

      queue_as :ghas_trial

      schedule interval: 24.hours, condition: -> { GitHub.billing_enabled? }

      retry_on ActiveJob::DeserializationError
      retry_on_dirty_exit

      BATCH_SIZE = 50

      sig { params(batch: T::Array[::Billing::SubscriptionItem], args: T.untyped, options: T.untyped).void }
      def process_batch(batch, *args, **options)
        batch.each do |subscription_item|
          # check for this, just in case expiry logic changes
          next if subscription_item.on_free_trial?
          ::Billing::AdvancedSecurity::SelfServeTrialCleanupJob.perform_later(subscription_item)
        end
      end

      private

      sig do
        params(
          args: T.untyped,
          timestamp: Time,
          offset_item_id: Integer,
          progress: Integer,
          options: T.untyped
        ).returns(T::Array[::Billing::SubscriptionItem])
      end
      def next_batch(*args, timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **options)
        subscribable = ::Billing::ProductUUID.where(::AdvancedSecurity::Public::Subscription::ADVANCED_SECURITY_MONTHLY_PRODUCT.serialize).take
        ::Billing::SubscriptionItem.
          where(subscribable: subscribable).
          where("id > ?", offset_item_id).
          active. # quantity > 0
          where("free_trial_ends_on > ? AND free_trial_ends_on < ?", 2.weeks.ago, 3.days.ago).
          limit(BATCH_SIZE).
          order(id: :asc).to_a
      end
    end
  end
end
