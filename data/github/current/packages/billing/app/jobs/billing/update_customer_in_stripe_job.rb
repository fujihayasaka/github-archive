# typed: strict
# frozen_string_literal: true

module Billing
  class UpdateCustomerInStripeJob < BillingJob
    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    class StripeCustomerDeleted < StandardError; end

    sig { params(dotcom_customer_id: Integer).returns(T.nilable(::Stripe::Customer)) }
    def perform(dotcom_customer_id)
      dotcom_customer = Customer.find_by(id: dotcom_customer_id)
      return unless dotcom_customer.present?

      stripe_customer = get_stripe_customer(dotcom_customer.id)
      create_or_update_stripe_customer(stripe_customer, dotcom_customer)
    end

    private

    sig { params(dotcom_customer_id: Integer).returns(T.nilable(::Stripe::Customer)) }
    def get_stripe_customer(dotcom_customer_id)
      log_context = {
        "code.namespace" => self.class.name,
        "code.function" => __method__,
        "gh.billing.customer.id" => dotcom_customer_id,
      }
      key = stripe_customer_id_key(dotcom_customer_id)
      stripe_customer_id = Billing::Kv.store.get(key).value!
      return unless stripe_customer_id.present?

      stripe_customer = ::Stripe::Customer.retrieve(stripe_customer_id, { api_key: GitHub.stripe_v3_api_key })
      raise StripeCustomerDeleted if stripe_customer.deleted?

      GitHub.dogstats.increment("billing.update_customer_in_stripe.customer_retrieved")
      GitHub.logger.info("customer retrieved", log_context.merge("gh.billing.stripe.customer.id" => stripe_customer.id))

      stripe_customer
    rescue ::Stripe::InvalidRequestError, StripeCustomerDeleted => e
      # There are two scenarios we need to handle here:
      #   1. InvalidRequestError - This means that the customer does not exist in Stripe.
      #   2. StripeCustomerDeleted - This means that the customer used to exist but was deleted.
      #
      # In both scenarios, we delete our reference to the customer to ensure we create a new one
      GitHub.logger.error(e, T.must(log_context).merge("gh.billing.stripe.customer.id" => stripe_customer_id))
      with_write { Billing::Kv.store.del(key) }
    end

    sig { params(stripe_customer: T.nilable(::Stripe::Customer), dotcom_customer: Customer).returns(::Stripe::Customer) }
    def create_or_update_stripe_customer(stripe_customer, dotcom_customer)
      changes = {}

      # Address + Name
      if (contact = dotcom_customer.billing_contact).persisted?
        if (address = address_changes(T.unsafe(stripe_customer)&.address.to_h, contact)).any?
          changes[:address] = address
        end

        if contact.fullname != stripe_customer&.name
          changes[:name] = contact.fullname
        end
      end

      # Shipping Address + Name
      if (contact = dotcom_customer.shipping_contact).persisted?
        shipping = {}

        if (address = address_changes(T.unsafe(stripe_customer)&.shipping&.address.to_h, contact)).any?
          shipping[:address] = address
        end

        if contact.fullname != T.unsafe(stripe_customer)&.shipping&.name
          shipping[:name] = contact.fullname
        end

        changes[:shipping] = shipping if shipping.any?
      end

      # Metadata
      if (metadata = metadata_changes(T.unsafe(stripe_customer)&.metadata.to_h, dotcom_customer)).any?
        changes[:metadata] = metadata
      end

      log_context = {
        "code.namespace" => self.class.name,
        "code.function" => __method__,
        "gh.billing.customer.id" => dotcom_customer.id,
        "gh.billing.stripe.customer.changes" => changes,
      }

      # Create or update the customer in Stripe
      if stripe_customer.nil?
        stripe_customer = ::Stripe::Customer.create(changes, { api_key: GitHub.stripe_v3_api_key })

        key = stripe_customer_id_key(dotcom_customer.id)
        with_write { Billing::Kv.store.set(key, stripe_customer.id) }

        GitHub.dogstats.increment("billing.update_customer_in_stripe.customer_created")
        GitHub.logger.info("customer created", log_context.merge("gh.billing.stripe.customer.id" => stripe_customer.id))
      elsif changes.any?
        stripe_customer = ::Stripe::Customer.update(stripe_customer.id, changes, { api_key: GitHub.stripe_v3_api_key })

        GitHub.dogstats.increment("billing.update_customer_in_stripe.customer_updated")
        GitHub.logger.info("customer updated", log_context.merge("gh.billing.stripe.customer.id" => stripe_customer.id))
      end

      stripe_customer
    end

    sig { params(stripe_address: T::Hash[String, String], contact: Billing::Contact).returns(T::Hash[String, String]) }
    def address_changes(stripe_address, contact)
      changes(stripe_address, {
        city: contact.city,
        country: contact.country_code,
        line1: contact.address1,
        line2: contact.address2,
        postal_code: contact.postal_code,
        state: contact.region,
      })
    end

    sig { params(stripe_metadata: T::Hash[String, String], dotcom_customer: Customer).returns(T::Hash[String, String]) }
    def metadata_changes(stripe_metadata, dotcom_customer)
      zuora_account_id = dotcom_customer.zuora_account_id
      zuora_account_url = zuora_account_id ? "#{GitHub.zuora_host}/apps/CustomerAccount.do?method=view&id=#{zuora_account_id}" : nil
      changes(stripe_metadata, {
        dotcom_customer_id: dotcom_customer.id,
        zuora_account_url: zuora_account_url,
      })
    end

    sig { params(old_hash: T::Hash[String, String], new_hash: T::Hash[String, String]).returns(T::Hash[String, String]) }
    def changes(old_hash, new_hash)
      new_hash.each_with_object({}) do |(key, value), changes|
        next if old_hash[key] == value
        changes[key] = value
      end
    end

    sig { params(dotcom_customer_id: Integer).returns(String) }
    def stripe_customer_id_key(dotcom_customer_id)
      "stripe_customer_id_for_dotcom_customer_#{dotcom_customer_id}"
    end
  end
end
