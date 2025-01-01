# typed: strict
# frozen_string_literal: true

module Copilot
  module Seat::BillingDependency
    extend ActiveSupport::Concern
    extend T::Helpers

    requires_ancestor { Copilot::Seat }

    BILLING_PLATFORM_V1_USAGE_EVENT = "billingplatform.v1.Usage"

    sig { params(quantity: Float, sku: String).void }
    def seat_prorated_billing_message_emission(quantity:, sku:)
      return unless can_emit_prorated_emission_billing_message?

      billing_message = prorated_billing_message(quantity: quantity, sku: sku)
      Hydro::PublishRetrier.publish(billing_message, schema: BILLING_PLATFORM_V1_USAGE_EVENT, publisher: GitHub.hydro_publisher)

      GitHub.logger.with_named_tags({
        customer_id: customer_id,
        user_id: assigned_user_id,
        billing_message: billing_message
      }) do
        GitHub.logger.info("Emitting prorated emission billing message")
      end

      GitHub.dogstats.increment("copilot.billing_vnext.seat_prorated_emission")
    end

    sig do
      params(quantity: Float, sku: String).returns(
      {
        sku: String,
        quantity: Float,
        usage_at: Time,
        usage_uuid: String,
        entity: T::Hash[String, Integer],
        source_uri: String,
      })
    end
    def prorated_billing_message(quantity:, sku:)
      # We use the current datetime to ensure that if we do somehow send multiple daily emissions for the same user,
      # only the first one will be recognized by the billing platform.
      # We use `Date.current.beginning_of_day` specifically so that we're matching the logic in `SeatEmission.can_emit?`,
      # to ensure that our two ways of ensuring one emission per day don't collide.
      date = Date.current.beginning_of_day
      create_billing_message("copilot_seat_emission", quantity, date, sku: sku)
    end

    private

    # The usage_uuid is used to dedup the billing platform usage events
    # We bill monthly, so we need to make sure if we send two add/remove events in the same month for the same user
    # they are deduped. We use the customer id since a user could belong to multiple orgs in an enterprise
    sig { params(prefix: String, date: T.any(Date, ActiveSupport::TimeWithZone)).returns(String) }
    def create_billing_message_uuid(prefix, date)
      Digest::SHA256.hexdigest(prefix + customer_id.to_s + ":" + date.strftime("%m/%d/%Y:%H:%M:%S") + ":" + assigned_user_id.to_s).to_s
    end

    sig do
      params(prefix: String, quantity: Float, date: T.any(Date, ActiveSupport::TimeWithZone), sku: String).returns(
      {
        sku: String,
        quantity: Float,
        usage_at: Time,
        usage_uuid: String,
        entity: T::Hash[String, Integer],
        source_uri: String,
      })
    end
    def create_billing_message(prefix, quantity, date, sku: "copilot_for_business")
      # the organization/business may not exist due to the deletion occuring in the job. If so we will need to create a standin
      # This will work because the global uri tool uses the model name and id
      # https://github.com/rails/globalid/blob/main/lib/global_id/uri/gid.rb#L67
      fake_entity = owner_type == "Organization" ? StandinOrg.new : StandinBiz.new
      fake_entity.id = owner_id

      message = {
        sku: sku,
        quantity: quantity,
        usage_at: Time.now, # What do we want this to be, should it be the month?
        usage_uuid: create_billing_message_uuid(prefix, date),
        entity: {
          customer_id: customer_id,
          actor_id: assigned_user_id,
        },
        source_uri: GlobalID.create(fake_entity).to_s,
      }

      # As part of the change to prorated emissions, we're going to include the organization ID
      # in the emission message
      if organization.present?
        message[:entity][:organization_id] = T.must(organization).id
      end

      message
    end

    sig { returns(T::Boolean) }
    def can_emit_prorated_emission_billing_message?
      # If the organization/business is being deleted, it will not exist to check for flags.
      # If we're emitting prorated, we can just stop emitting.
      return false if owner.nil?
      return false unless copilot_via_billing_vnext?

      # Ensure they are in the vnext flag, and the org has copilot for business.
      return false if customer_id.nil?

      true
    end

    sig { returns(T::Boolean) }
    def copilot_via_billing_vnext?
      return true if ::FeatureFlag.vexi.enabled?(:cutoff_emissions_to_meuse, default: false)

      !!::BillingPlatformEnabledProduct.find_by(customer_id: customer_id)&.copilot
    end

    class StandinOrg
      sig { returns(T.nilable(String)) }
      def self.name
        ::Organization.name
      end
      sig { returns(T.nilable(Integer)) }
      attr_accessor :id
    end

    class StandinBiz
      sig { returns(T.nilable(String)) }
      def self.name
        ::Business.name
      end
      sig { returns(T.nilable(Integer)) }
      attr_accessor :id
    end
  end
end
