# typed: strict
# frozen_string_literal: true

module Billing
  # Publishes subscription lifecycle domain events to Hydro.
  #
  # These are proper domain events (not audit logs or telemetry) following
  # the domain isolation events pattern. Consumers subscribe via
  # HydroMessageJob through the Aqueduct bridge.
  #
  # Uses GitHub.aqueduct_fallback_hydro_publisher for reliable delivery
  # (synchronous attempt + Aqueduct fallback on failure).
  #
  module SubscriptionEventPublisher
    SCHEMA_PREFIX = "github.billing.v1"

    sig do
      params(
        subscription_item: ::Billing::SubscriptionItem,
        actor: T.nilable(::User),
        is_stafftools_action: T::Boolean,
      ).void
    end
    def self.subscription_item_created(
      subscription_item:,
      actor:,
      is_stafftools_action: false
    )
      payload = {
        event_id: "si_created_#{subscription_item.id}_#{Time.current.to_i}",
        context: build_context(subscription_item:, actor:),
        is_stafftools_action:,
      }

      publish(
        payload,
        schema: "#{SCHEMA_PREFIX}.SubscriptionItemCreated",
        partition_key: subscription_item.plan_subscription_id.to_s,
      )
    end

    sig do
      params(
        subscription_item: ::Billing::SubscriptionItem,
        actor: T.nilable(::User),
        previous_quantity: Integer,
        was_on_free_trial: T::Boolean,
        force_cancelled: T::Boolean,
      ).void
    end
    def self.subscription_item_cancelled(
      subscription_item:,
      actor:,
      previous_quantity:,
      was_on_free_trial: false,
      force_cancelled: false
    )
      payload = {
        event_id: "si_cancelled_#{subscription_item.id}_#{Time.current.to_i}",
        context: build_context(subscription_item:, actor:),
        previous_quantity:,
        was_on_free_trial:,
        force_cancelled:,
      }

      publish(
        payload,
        schema: "#{SCHEMA_PREFIX}.SubscriptionItemCancelled",
        partition_key: subscription_item.plan_subscription_id.to_s,
      )
    end

    sig do
      params(
        subscription_item: ::Billing::SubscriptionItem,
        actor: T.nilable(::User),
        old_product_type: String,
        old_product_key: String,
        old_billing_cycle: String,
        old_quantity: Integer,
        is_pending: T::Boolean,
        effective_at: T.nilable(Date),
      ).void
    end
    def self.subscription_item_changed(
      subscription_item:,
      actor:,
      old_product_type:,
      old_product_key:,
      old_billing_cycle:,
      old_quantity:,
      is_pending: false,
      effective_at: nil
    )
      payload = {
        event_id: "si_changed_#{subscription_item.id}_#{Time.current.to_i}",
        context: build_context(subscription_item:, actor:),
        old_product_type:,
        old_product_key:,
        old_billing_interval: billing_interval_enum(old_billing_cycle),
        old_quantity:,
        is_pending:,
        effective_at: effective_at&.to_time,
      }

      publish(
        payload,
        schema: "#{SCHEMA_PREFIX}.SubscriptionItemChanged",
        partition_key: subscription_item.plan_subscription_id.to_s,
      )
    end

    class << self
      private

      sig do
        params(
          payload: T::Hash[Symbol, T.untyped],
          schema: String,
          partition_key: String,
        ).void
      end
      def publish(payload, schema:, partition_key:)
        GitHub.aqueduct_fallback_hydro_publisher.publish(
          payload,
          schema:,
          partition_key:,
        )
      end

      sig do
        params(
          subscription_item: ::Billing::SubscriptionItem,
          actor: T.nilable(::User),
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def build_context(subscription_item:, actor:)
        plan_subscription = subscription_item.plan_subscription
        subscribable = subscription_item.subscribable
        account = plan_subscription&.billable_entity

        {
          subscription_item_id: subscription_item.id,
          plan_subscription_id: plan_subscription&.id,
          billable_entity_type: billable_entity_type_enum(account),
          billable_entity_id: account&.id,
          customer_id: plan_subscription&.customer_id,
          organization_id: subscription_item.organization_id,
          product_type: subscribable.product_type,
          product_key: subscribable.product_key,
          billing_interval: billing_interval_enum(subscribable.billing_cycle),
          actor_id: actor&.id,
          quantity: subscription_item.quantity,
          free_trial_ends_on: subscription_item.free_trial_ends_on&.to_time,
          on_free_trial: subscription_item.on_free_trial?,
          subscribable_id: subscribable&.id,
          subscribable_type: subscribable&.class&.name,
          in_app_purchase_vendor: subscription_item.in_app_purchase&.type&.serialize,
          in_app_purchase_identifier: subscription_item.in_app_purchase&.identifier,
          occurred_at: Time.current,
        }
      end

      BILLING_INTERVAL_MAP = T.let({
        "month" => :MONTHLY,
        "year" => :YEARLY,
        "one_time" => :ONE_TIME,
      }.freeze, T::Hash[String, Symbol])

      sig { params(billing_cycle: T.nilable(String)).returns(Symbol) }
      def billing_interval_enum(billing_cycle)
        BILLING_INTERVAL_MAP.fetch(billing_cycle.to_s, :BILLING_INTERVAL_UNKNOWN)
      end

      sig { params(account: T.nilable(::Billing::Types::Account)).returns(Symbol) }
      def billable_entity_type_enum(account)
        case account
        when ::Business then :BUSINESS
        when ::User then :USER # Organization < User, so orgs map to USER
        else :BILLABLE_ENTITY_TYPE_UNKNOWN
        end
      end
    end
  end
end
