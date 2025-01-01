# typed: strict
# frozen_string_literal: true

# MeteredAdvancedSecurityScheduledEmitterJob iterates through Businesses that are using GHAS metered billing
# and emits their seat count.
class MeteredAdvancedSecurityScheduledEmitterJob < ApplicationJob
  class BusinessEmitterJob < ApplicationJob
    extend T::Sig
    queue_as :advanced_security

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    locked_by timeout: 1.hour, key: ->(job) {
      job.arguments[0]
    }

    sig { params(business_id: Integer, usage_id: String).void }
    def perform(business_id:, usage_id:)
      usage_at = DateTime.now.utc

      business = Business.find_by!(id: business_id)

      resp = GitHub::Turboghas.client.get_meter_emissions(
        entity_type: :ENTITY_TYPE_BUSINESS,
        entity_id: business.id,
        customer_id: business.customer_id,
      )

      raise StandardError.new(resp.error.to_s) if resp.error

      (resp.data.added.map { |v| [v, 1, "+"] } + resp.data.removed.map { |v| [v, -1, "-"] }).each do |user_id, quantity, type|
        usage_message = {
          sku: "ghas_seats",
          quantity: quantity,
          usage_at: Google::Protobuf::Timestamp.new(seconds: usage_at.to_i, nanos: 0),
          source_uri: GlobalID.create(business.customer).to_s,
          usage_uuid: Digest::UUID.uuid_v5(Digest::UUID::OID_NAMESPACE, "GHAS/#{usage_id}/#{business.id}/#{user_id}/#{type}"), # rubocop:disable GitHub/InsecureHashAlgorithm
          entity: {
            customer_id: business.customer_id,
            actor_id: user_id,
          }
        }

        GitHub.logger.info(
          "emitting ghas_seats usage",
          "gh.business.ghas_seats": usage_message[:quantity],
          usage_uuid: usage_message[:usage_uuid],
          usage_at: usage_at,
          entity_customer_id: usage_message[:entity][:customer_id],
          entity_actor_id: usage_message[:entity][:actor_id],
          business_id: business.id,
        )

        Hydro::PublishRetrier.publish(usage_message, schema: "billingplatform.v1.Usage", publisher: GitHub.hydro_publisher)

        if quantity == 1
          GitHub.dogstats.increment("advanced_security.ghas_seats.added")
        elsif quantity == -1
          GitHub.dogstats.increment("advanced_security.ghas_seats.removed")
        end
      end

      GitHub.dogstats.increment("advanced_security.meter")
    end
  end

  extend T::Sig
  queue_as :advanced_security
  schedule interval: 1.hour, condition: -> { !GitHub.enterprise? }

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  sig { void }
  def perform
    started_at = DateTime.now.utc
    find_businesses_for_azure_emission.each do |business|
      BusinessEmitterJob.perform_later(business_id: T.must(business.id), usage_id: job_id)
    end
  end

  sig { returns(T::Enumerator[Business]) }
  def find_businesses_for_azure_emission
    # Here we bypass the Configurable logic for fetching and caching configs
    # because the number of repos could be very large and we know we only
    # care about configuration set at the business level here.
    Enumerator.new do |out|
      Configuration::Entry
        .where({
          target_type: :Business,
          name: Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_KEY,
          value: Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_ENABLED_METERED_BILLING,
        })
        .preload(:target)
        .find_in_batches do |batch|
          batch.map(&:target).each do |business|
            out << business if business && business.customer.present?
          end
        end
    end
  end
end
