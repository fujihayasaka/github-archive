# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

# MeteredAdvancedSecurityScheduledEmitterJob iterates through Businesses that are using GHAS metered billing
# and emits their seat count.
class MeteredAdvancedSecurityScheduledEmitterJob < ApplicationJob

  queue_as :advanced_security
  schedule interval: 1.hour, condition: -> { !GitHub.enterprise? }

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  class BusinessEmitterJob < ApplicationJob
    queue_as :advanced_security

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    locked_by timeout: 1.hour, key: ->(job) {
      job.arguments[0]
    }

    sig { params(sku: GitHub::Turboghas::SKU, business: Business).returns(String) }
    private_class_method def self.unmatched_ids_key(sku:, business:)
      "#{sku.emission_sku}/#{business.id}/connect-unmatched"
    end

    sig { params(sku: GitHub::Turboghas::SKU, business: Business, unmatched_ids: T::Array[Integer]).void }
    def self.update_unmatched_ids!(sku:, business:, unmatched_ids:)
      unmatched_key = unmatched_ids_key(sku:, business:)
      ActiveRecord::Base.connected_to(role: :writing) do
        if unmatched_ids.empty?
          CodeScanning::KV.store.del(unmatched_key)
        else
          CodeScanning::KV.store.set(unmatched_key, Base64.urlsafe_encode64(MessagePack.pack(unmatched_ids.sort.to_a)), expires: business.next_metered_billing_cycle_starts_at)
        end
      end
    end

    sig { params(sku: GitHub::Turboghas::SKU, business: Business).returns(T.nilable(T::Array[Integer])) }
    def self.unmatched_ids(sku:, business:)
      unmatched_key = unmatched_ids_key(sku:, business:)
      previous_unmatched = CodeScanning::KV.store.get(unmatched_key).value!
      if previous_unmatched
        MessagePack.unpack(Base64.urlsafe_decode64(previous_unmatched))
      end
    end

    sig { params(business_id: Integer, usage_id: String, usage_at: DateTime).void }
    def perform(business_id:, usage_id:, usage_at: DateTime.now.beginning_of_hour)
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

        skus = T.let([], T::Array[GitHub::Turboghas::SKU])
        if business.advanced_security_products_bundled?
          skus << GitHub::Turboghas::SKU::Bundled
        else
          skus << GitHub::Turboghas::SKU::CodeSecurity if business.code_security_purchased?
          skus << GitHub::Turboghas::SKU::SecretSecurity if business.secret_protection_purchased?
        end
        skus.each do |sku|
          emission_sku = sku.emission_sku

          # add the set of user ids we got from GitHub Connect if available
          # so turboghas can include them in the meter readings
          ghes_committers = business.advanced_security_license_for_sku(sku:).ghes_committers
          GitHub.logger.info(
            "business has additional users from connect",
            "gh.customer.id": customer.id,
            "additional_users_count": ghes_committers.user_ids.size,
            "unmatched_user_ids": ghes_committers.unmatched.size,
            "sku": emission_sku,
          ) unless ghes_committers.nil?

          # Get a set of all users that are active in the last billing cycle
          resp = GitHub::Turboghas.client.get_meter_emissions(
            **sku.to_proto,
            entity_type: :ENTITY_TYPE_BUSINESS,
            entity_id: business.id,
            customer_id: business.customer_id,
            additional_user_ids: ghes_committers&.user_ids,
            current_billing_period_started_at: business.current_metered_billing_cycle_starts_at.to_time
          )
          raise StandardError.new(resp.error.to_s) if resp.error

          # use KV to keep track of the users we previously emitted
          # add them back into the set and emit them for the entire billing period
          unmatched = Set.new(ghes_committers&.unmatched || [])
          previous_unmatched_ids = MeteredAdvancedSecurityScheduledEmitterJob::BusinessEmitterJob.unmatched_ids(sku:, business:)
          if previous_unmatched_ids
            newly_matched_ids = business.advanced_security_business_user_accounts(sku:)
              .where({ enterprise_installation_user_accounts: { id: previous_unmatched_ids } })
              .where.not(user_id: nil)
              .pluck(enterprise_installation_user_accounts: :id)
            unmatched.merge(previous_unmatched_ids - newly_matched_ids)
          end
          MeteredAdvancedSecurityScheduledEmitterJob::BusinessEmitterJob.update_unmatched_ids!(sku:, business:, unmatched_ids: unmatched.to_a)
          unless unmatched.empty?
            additional_usage_message = {
              sku: emission_sku,
              quantity: MeteredAdvancedSecurityScheduledEmitterJob.per_seat_rate(owner: business) * unmatched.size,
              usage_at: Google::Protobuf::Timestamp.new(seconds: usage_at.to_i, nanos: 0),
              source_uri: GlobalID.create(customer).to_s,
              usage_uuid: Digest::UUID.uuid_v5(Digest::UUID::OID_NAMESPACE, "#{emission_sku}/#{business_id}/connect/#{usage_at.beginning_of_day.to_i}"), # rubocop:disable GitHub/InsecureHashAlgorithm
              entity: { customer_id: }
            }
            GitHub.logger.info(
              "emitting #{emission_sku} usage",
              "gh.business.#{emission_sku}": additional_usage_message[:quantity],
              usage_uuid: additional_usage_message[:usage_uuid],
              usage_at:,
              entity_customer_id: additional_usage_message[:entity][:customer_id],
            )

            Hydro::PublishRetrier.publish(additional_usage_message, schema: "billingplatform.v1.Usage", publisher: GitHub.hydro_publisher)
          end

          resp.data.added.each do |actor_id|
            usage_message = {
              sku: emission_sku,
              quantity: MeteredAdvancedSecurityScheduledEmitterJob.per_seat_rate(owner: business),
              usage_at: Google::Protobuf::Timestamp.new(seconds: usage_at.to_i, nanos: 0),
              source_uri: GlobalID.create(customer).to_s,
              usage_uuid: Digest::UUID.uuid_v5(Digest::UUID::OID_NAMESPACE, "#{emission_sku}/#{business_id}/#{actor_id}/#{usage_id}"), # rubocop:disable GitHub/InsecureHashAlgorithm
              entity: { customer_id:, actor_id: }
            }

            GitHub.logger.info(
              "emitting #{emission_sku} usage",
              "gh.business.#{emission_sku}": usage_message[:quantity],
              usage_uuid: usage_message[:usage_uuid],
              usage_at:,
              entity_customer_id: usage_message[:entity][:customer_id],
              entity_actor_id: usage_message[:entity][:actor_id],
            )

            Hydro::PublishRetrier.publish(usage_message, schema: "billingplatform.v1.Usage", publisher: GitHub.hydro_publisher)

            GitHub.dogstats.increment("advanced_security.#{emission_sku}.added")
          end
          GitHub.dogstats.increment("advanced_security.meter")
        end
      end
    end
  end

  class UserEmitterJob < ApplicationJob
    queue_as :advanced_security

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    locked_by timeout: 1.hour, key: ->(job) {
      job.arguments[0]
    }

    sig { params(user_id: Integer, usage_id: String, usage_at: DateTime).void }
    def perform(user_id:, usage_id:, usage_at: DateTime.now.beginning_of_hour)
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

        skus = T.let([], T::Array[GitHub::Turboghas::SKU])
        if user.advanced_security_products_bundled?
          skus << GitHub::Turboghas::SKU::Bundled
        else
          skus << GitHub::Turboghas::SKU::CodeSecurity if user.code_security_purchased?
          skus << GitHub::Turboghas::SKU::SecretSecurity if user.secret_protection_purchased?
        end

        skus.each do |sku|
          emission_sku = sku.emission_sku
          # Get a set of all users that are active in the last billing cycle
          resp = GitHub::Turboghas.client.get_meter_emissions(
            **sku.to_proto,
            entity_type: :ENTITY_TYPE_USER,
            entity_id: user.id,
            customer_id:,
            current_billing_period_started_at: user.current_metered_billing_cycle_starts_at.to_time
          )
          raise StandardError.new(resp.error.to_s) if resp.error
          resp.data.added.each do |actor_id|
            usage_message = {
              sku: emission_sku,
              quantity: MeteredAdvancedSecurityScheduledEmitterJob.per_seat_rate(owner: user),
              usage_at: Google::Protobuf::Timestamp.new(seconds: usage_at.to_i, nanos: 0),
              source_uri: GlobalID.create(customer).to_s,
              usage_uuid: Digest::UUID.uuid_v5(Digest::UUID::OID_NAMESPACE, "#{emission_sku}/u/#{user_id}/#{actor_id}/#{usage_id}"), # rubocop:disable GitHub/InsecureHashAlgorithm
              entity: { customer_id:, actor_id: }
            }

            GitHub.logger.info(
              "emitting #{emission_sku} usage",
              "gh.business.#{emission_sku}": usage_message[:quantity],
              usage_uuid: usage_message[:usage_uuid],
              usage_at:,
              entity_customer_id: usage_message[:entity][:customer_id],
              entity_actor_id: usage_message[:entity][:actor_id],
            )

            Hydro::PublishRetrier.publish(usage_message, schema: "billingplatform.v1.Usage", publisher: GitHub.hydro_publisher)
            GitHub.dogstats.increment("advanced_security.#{emission_sku}.added")
          end

          GitHub.dogstats.increment("advanced_security.meter")
        end
      end
    end
  end

  sig { void }
  def perform
    usage_at = DateTime.now.beginning_of_hour

    find_businesses_for_azure_emission.each do |business|
      BusinessEmitterJob.perform_later(business_id: T.cast(business.id, Integer), usage_id: job_id, usage_at:)
    end

    find_users_for_azure_emission.each do |user|
      UserEmitterJob.perform_later(user_id: user.id, usage_id: job_id, usage_at:)
    end
  end

  sig { returns(T::Enumerator[User]) }
  def find_users_for_azure_emission
    Enumerator.new do |out|
      Configuration::Entry
        .where({
          target_type: :User,
          name: Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_KEY,
          value: [
            Configurable::AdvancedSecurityBillingConfig::GHAS_METERED,
            Configurable::AdvancedSecurityBillingConfig::SPLIT_METERED
          ],
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
          value: [
            Configurable::AdvancedSecurityBillingConfig::GHAS_METERED,
            Configurable::AdvancedSecurityBillingConfig::SPLIT_METERED
          ],
        })
        .preload(:target)
        .find_in_batches do |batch|
          batch.map(&:target).each do |business|
            out << business if business && business.customer.present?
          end
        end
    end
  end

  sig { params(owner: T.any(Business, User)).returns(Float) }
  def self.per_seat_rate(owner:)
    number_of_days_in_billing_cycle = (owner.next_metered_billing_cycle_starts_at.to_date - owner.current_metered_billing_cycle_starts_at.to_date).to_f
    (1.0 / number_of_days_in_billing_cycle).truncate(9).to_f
  end
end
