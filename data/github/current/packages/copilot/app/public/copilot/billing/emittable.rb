# typed: strict
# frozen_string_literal: true

module Copilot
  module Billing
    class Emittable
      include GitHub::Memoizer

      sig { returns(T.any(::Business, ::Organization)) }
      attr_reader :owner

      sig { returns(T::Set[Integer]) }
      attr_reader :already_billed_user_ids

      sig { params(owner: T.any(::Business, ::Organization), already_billed_user_ids: T::Set[Integer]).void }
      def initialize(owner, already_billed_user_ids: Set.new)
        @owner = owner
        @already_billed_user_ids = already_billed_user_ids
      end

      sig { returns(Float) }
      memoize def quantity
        seat_count * per_seat_rate
      end

      sig { returns(Float) }
      memoize def seat_count
        if copilot_owner.copilot_standalone? # this will return false if owner is an Organization
          # standalone_enterprise_seats is a grouped AR::Relation so we need to call .count TWICE to get the total number of seats with unique assigned_user_ids
          standalone_enterprise_seats.count.count.to_f
        elsif owner_is_business?
          enterprise_seats.count.count.to_f
        else
          organization_seats.count.to_f
        end
      end

      sig { returns(Float) }
      memoize def per_seat_rate
        (1.0 / number_of_days_in_billing_cycle).truncate(9).to_f
      end

      sig { returns(Float) }
      memoize def number_of_days_in_billing_cycle
        (owner.next_metered_billing_cycle_starts_at.to_date - owner.current_metered_billing_cycle_starts_at.to_date).to_f
      end

      sig { returns(T::Array[Integer]) }
      memoize def actor_ids
        if copilot_owner.copilot_standalone? # this will return false if owner is an Organization
          standalone_enterprise_seats.pluck(:assigned_user_id)
        elsif owner_is_business?
          enterprise_seats.pluck(:assigned_user_id)
        else
          organization_seats.pluck(:assigned_user_id)
        end
      end

      sig do
        returns(
          {
            usage_uuid: String,
            product_name: String,
            product_sku_name: String,
            usage_at: Time,
            quantity: Float,
            account_id: T.nilable(Integer),
            customer_id: T.nilable(Integer),
            custom_fields: T::Hash[String, String],
            source_uri: String,
            billing_target: T.nilable(String)
          }
        )
      end
      def meuse_emission_payload
        custom_fields = {}

        payload = {
          usage_uuid: SecureRandom.uuid,
          product_name: "copilot",
          product_sku_name: product_sku_name,
          usage_at: DateTime.now.utc,
          quantity: quantity,
          account_id: T.let(nil, T.nilable(Integer)),
          customer_id: T.let(nil, T.nilable(Integer)),
          custom_fields: custom_fields,
          source_uri: GlobalID.create(owner).to_s,
          billing_target: billing_target(customer: owner.customer)
        }

        if owner_is_business?
          payload[:customer_id] = T.cast(owner, ::Business).customer_id
        else
          payload[:account_id] = owner.id
        end

        payload
      end

      sig do
        returns(
          {
            product_name: String,
            product_sku_name: String,
            quantity: Float,
            usage_at: Time,
            billing_target: T.nilable(String),
            actor_ids: T::Array[Integer],
            usage_uuid: String,
            account_id: T.nilable(Integer),
            customer_id: T.nilable(Integer),
          }
        )
      end
      def billing_platform_payload
        payload = {
          product_name: "copilot",
          product_sku_name: product_sku_name,
          quantity: quantity,
          usage_at: Time.now,
          billing_target: T.let(nil, T.nilable(String)),
          actor_ids: actor_ids,
          usage_uuid: SecureRandom.uuid,
          account_id: T.let(nil, T.nilable(Integer)),
          customer_id: T.let(nil, T.nilable(Integer)),
        }

        if owner_is_business?
          payload[:customer_id] = T.cast(owner, ::Business).customer_id
          payload[:billing_target] = billing_target(customer: T.cast(owner, ::Business).customer)
        else
          payload[:customer_id] = T.cast(owner, ::Organization).customer_for(:general, delegate_to_business: true)&.id
          payload[:billing_target] = billing_target(customer: T.cast(owner, ::Organization).customer_for(:general, delegate_to_business: true))
        end

        payload
      end

      sig { returns(ActiveRecord::Relation) }
      memoize def organization_seats
        if owner.id == Copilot::MS_COPILOT_ORG_ID
          # only get the ACTIVE users
          return Copilot::Seat.
            joins("INNER JOIN copilot_aggregate_usage_details on copilot_aggregate_usage_details.user_id = copilot_seats.assigned_user_id").
            for_organization(owner).
            where.not(assigned_user_id: already_billed_user_ids).
            where("copilot_aggregate_usage_details.updated_at > ?", 24.hours.ago)
        end
        Copilot::Seat.for_organization(owner).where.not(assigned_user_id: already_billed_user_ids)
      end

      # With the .group call on assigned_user_id, we are ensuring that we are only counting each user once
      # Beware that calling .count on this result will return a hash of unique assigned_user_id's and their counts
      sig { returns(ActiveRecord::Relation) }
      memoize def standalone_enterprise_seats
        Copilot::Seat
          .joins(:seat_assignment)
          .where(copilot_seat_assignments: {
            owner_id: owner.id,
            owner_type: "Business",
            organization_id: nil,
            assignable_type: %w(EnterpriseTeam User)
          })
          .group(:assigned_user_id)
      end

      sig { returns(ActiveRecord::Relation) }
      memoize def enterprise_seats
        Copilot::Seat
          .joins(:seat_assignment)
          .where(copilot_seat_assignments: {
            owner_id: owner.id,
            owner_type: "Business",
          })
          .where.not(assigned_user_id: already_billed_user_ids)
          .group(:assigned_user_id)
      end

      sig { returns(T.any(Copilot::Business, Copilot::Organization)) }
      memoize def copilot_owner
        if owner_is_business?
          Copilot::Business.new(T.cast(owner, ::Business))
        else
          Copilot::Organization.new(T.cast(owner, ::Organization))
        end
      end

      sig { returns(String) }
      memoize def product_sku_name
        if copilot_owner.copilot_plan_enterprise?
          # If the user has already purchased CE, make sure that any active CE trials are still charged with the CB SKU
          return "copilot_for_business" if copilot_owner.on_free_copilot_enterprise_trial?

          "copilot_enterprise"
        elsif copilot_owner.copilot_standalone?
          "copilot_standalone"
        else
          "copilot_for_business"
        end
      end

      sig { params(customer: T.nilable(Customer)).returns(T.nilable(String)) }
      def billing_target(customer:)
        if customer&.requires_azure_subscription?
          "Azure"
        else
          "Zuora"
        end
      end

      private

      sig { returns(T::Boolean) }
      memoize def owner_is_business?
        owner.is_a?(::Business)
      end
    end
  end
end
