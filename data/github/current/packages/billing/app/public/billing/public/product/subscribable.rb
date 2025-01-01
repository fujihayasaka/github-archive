# typed: strict
# frozen_string_literal: true

module  Billing
  module Public
    module Product
      module Subscribable
        extend T::Sig

        sig do
          params(
            product_uuid_attributes: Billing::Public::Product::ProductIdentifier,
            actor: User,
            quantity: Integer,
            free_trial_length: ActiveSupport::Duration,
            is_stafftools_action: T::Boolean,
            skip_sync: T::Boolean,
          ).returns(GitHub::Result)
        end
        def subscribe_to_product(product_uuid_attributes, actor:, quantity: 1, free_trial_length: 0.days, is_stafftools_action: false, skip_sync: false)
          T.bind(self, T.any(User, Business))

          result = Billing::Public::SubscriptionItem.create(
            product: product_uuid_attributes,
            account: self,
            actor: actor,
            free_trial_length: free_trial_length,
            quantity: quantity,
            is_stafftools_action: is_stafftools_action,
            skip_sync: skip_sync,
          )

          unless result.ok?
            GitHub::Logger.log_exception({
              method: "billing.public.product.subscribable.subscribe_to_product", tags: ["product_type: #{product_uuid_attributes.product_type}"],
              product: product_uuid_attributes.product_type
            }, result.error)

            GitHub.dogstats.increment("billing.public.product.subscribe_to_product.error", tags: ["product_type: #{product_uuid_attributes.product_type}"])
          end

          result
        end

        sig do
          params(
            product_uuid_attributes: Billing::Public::Product::ProductIdentifier,
          ).returns(T::Boolean)
        end
        def subscribed_to_product?(product_uuid_attributes)
          T.bind(self, T.any(User, Business, Organization))

          ::Billing::Public::SubscriptionItem.all_active(product: product_uuid_attributes, account: self).value { [] }.present?
        end

        sig do
          params(
            product_uuid_attributes: T.any(Billing::Public::Product::ProductIdentifier, Billing::ProductUUID),
            actor: User,
            force: T::Boolean,
            skip_sync: T::Boolean,
          ).returns(GitHub::Result)
        end
        def cancel_product_subscription(product_uuid_attributes, actor:, force: false, skip_sync: false)
          T.bind(self, T.any(User, Organization, Business))

          result = Billing::Public::SubscriptionItem.cancel(product: product_uuid_attributes, account: self, actor: actor, force: force, skip_sync: skip_sync)
          unless result.ok?
            GitHub::Logger.log_exception({
              method: "billing.public.product.subscribable.cancel_product_subscription", tags: ["product_type: #{product_uuid_attributes.product_type}"],
              product: product_uuid_attributes.product_type
            }, result.error)

            GitHub.dogstats.increment("billing.public.product.cancel_product_subscription.error", tags: ["product_type: #{product_uuid_attributes.product_type}"])
          end

          result
        end
      end
    end
  end
end
