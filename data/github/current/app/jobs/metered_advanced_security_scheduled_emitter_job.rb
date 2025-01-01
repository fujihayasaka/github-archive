# typed: strict
# frozen_string_literal: true

# MeteredAdvancedSecurityScheduledEmitterJob iterates through Businesses that are using GHAS metered billing
# and emits their seat count.
class MeteredAdvancedSecurityScheduledEmitterJob < ApplicationJob
  class BusinessEmitterJob < ApplicationJob
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

      GitHub.logger.with_named_tags(
        "code.namespace": "MeteredAdvancedSecurityScheduledEmitterJob::BusinessEmitterJob",
        "code.function": "perform",
        "gh.business.id": business.id,
      ) do
        return GitHub.logger.error("business must be the advanced_security_billable_entity") unless business.advanced_security_billable_entity?
        return GitHub.logger.error("business must be using metered billing") unless business.advanced_security_metered_for_entity?

        customer = business.customer

        return GitHub.logger.error("could not emit metered billing for business without customer") if customer.nil?

        customer_id = customer.id

        # add the set of user ids we got from GitHub Connect if available
        # so turboghas can include them in the meter readings
        additional_user_ids = business.advanced_security_business_user_ids
        GitHub.logger.info(
          "business has additional users from connect",
          "gh.customer.id": customer.id,
          "additional_users_count": additional_user_ids.length,
        )

        resp = GitHub::Turboghas.client.get_meter_emissions(
          entity_type: :ENTITY_TYPE_BUSINESS,
          entity_id: business.id,
          customer_id: business.customer_id,
          additional_user_ids: (additional_user_ids if business.feature_enabled?(:ghas_metered_additional_committers)),
        )

        raise StandardError.new(resp.error.to_s) if resp.error

        (resp.data.added.map { |v| [v, 1, "+"] } + resp.data.removed.map { |v| [v, -1, "-"] }).each do |actor_id, quantity, type|
          usage_message = {
            sku: "ghas_seats",
            quantity: quantity,
            usage_at: Google::Protobuf::Timestamp.new(seconds: usage_at.to_i, nanos: 0),
            source_uri: GlobalID.create(customer).to_s,
            usage_uuid: Digest::UUID.uuid_v5(Digest::UUID::OID_NAMESPACE, "GHAS/#{usage_id}/#{business_id}/#{actor_id}/#{type}"), # rubocop:disable GitHub/InsecureHashAlgorithm
            entity: { customer_id:, actor_id: }
          }

          GitHub.logger.info(
            "emitting ghas_seats usage",
            "gh.business.ghas_seats": usage_message[:quantity],
            usage_uuid: usage_message[:usage_uuid],
            usage_at:,
            entity_customer_id: usage_message[:entity][:customer_id],
            entity_actor_id: usage_message[:entity][:actor_id],
          )

          Hydro::PublishRetrier.publish(usage_message, schema: "billingplatform.v1.Usage", publisher: GitHub.hydro_publisher)

          if quantity == 1
            GitHub.dogstats.increment("advanced_security.ghas_seats.added")
          elsif quantity == -1
            GitHub.dogstats.increment("advanced_security.ghas_seats.removed")
          end
        end
      end

      GitHub.dogstats.increment("advanced_security.meter")
    end
  end

  class UserEmitterJob < ApplicationJob
    queue_as :advanced_security

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    locked_by timeout: 1.hour, key: ->(job) {
      job.arguments[0]
    }

    sig { params(user_id: Integer, usage_id: String).void }
    def perform(user_id:, usage_id:)
      usage_at = DateTime.now.utc

      user = User.find_by!(id: user_id)

      GitHub.logger.with_named_tags(
        "code.namespace": "MeteredAdvancedSecurityScheduledEmitterJob::UserEmitterJob",
        "code.function": "perform",
        "gh.user.id": user.id,
      ) do
        return GitHub.logger.error("user must be the advanced_security_billable_entity") unless user.advanced_security_billable_entity?
        return GitHub.logger.error("user must be using metered billing") unless user.is_a?(Organization) && user.advanced_security_metered_for_entity?

        customer = user.customer

        return GitHub.logger.error("could not emit metered billing for user without customer") if customer.nil?

        customer_id = customer.id

        resp = GitHub::Turboghas.client.get_meter_emissions(
          entity_type: :ENTITY_TYPE_USER,
          entity_id: user.id,
          customer_id:,
        )

        raise StandardError.new(resp.error.to_s) if resp.error

        (resp.data.added.map { |v| [v, 1, "+"] } + resp.data.removed.map { |v| [v, -1, "-"] }).each do |actor_id, quantity, type|
          usage_message = {
            sku: "ghas_seats",
            quantity: quantity,
            usage_at: Google::Protobuf::Timestamp.new(seconds: usage_at.to_i, nanos: 0),
            source_uri: GlobalID.create(customer).to_s,
            usage_uuid: Digest::UUID.uuid_v5(Digest::UUID::OID_NAMESPACE, "GHAS/#{usage_id}/u/#{user_id}/#{actor_id}/#{type}"), # rubocop:disable GitHub/InsecureHashAlgorithm
            entity: {
              customer_id:,
              actor_id:,
            }
          }

          GitHub.logger.info(
            "emitting ghas_seats usage",
            "gh.business.ghas_seats": usage_message[:quantity],
            usage_uuid: usage_message[:usage_uuid],
            usage_at:,
            entity_customer_id: usage_message[:entity][:customer_id],
            entity_actor_id: usage_message[:entity][:actor_id],
          )

          Hydro::PublishRetrier.publish(usage_message, schema: "billingplatform.v1.Usage", publisher: GitHub.hydro_publisher)

          if quantity == 1
            GitHub.dogstats.increment("advanced_security.ghas_seats.added")
          elsif quantity == -1
            GitHub.dogstats.increment("advanced_security.ghas_seats.removed")
          end
        end
      end

      GitHub.dogstats.increment("advanced_security.meter")
    end
  end

  queue_as :advanced_security
  schedule interval: 1.hour, condition: -> { !GitHub.enterprise? }

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  sig { void }
  def perform
    find_businesses_for_azure_emission.each do |business|
      BusinessEmitterJob.perform_later(business_id: T.must(business.id), usage_id: job_id)
    end

    find_users_for_azure_emission.each do |user|
      UserEmitterJob.perform_later(user_id: T.must(user.id), usage_id: job_id)
    end
  end

  sig { returns(T::Enumerator[User]) }
  def find_users_for_azure_emission
    Enumerator.new do |out|
      Configuration::Entry
        .where({
          target_type: :User,
          name: Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_KEY,
          value: Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_ENABLED_METERED_BILLING,
        })
        .preload(:target)
        .find_in_batches do |batch|
          batch.map(&:target).each do |user|
            out << user if user && user.customer.present?
          end
        end
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
