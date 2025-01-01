# typed: strict
# frozen_string_literal: true

class UpdateZuoraAccountInformationJob < BillingJob
  extend T::Sig
  include GitHub::Billing::ZuoraRateLimitHandler

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  queue_as :billing

  ::Billing::Zuora::RETRYABLE_ERRORS.each do |error|
    retry_on(error, wait: :polynomially_longer) do |_job, error|
      Failbot.report(error)
    end
  end

  rescue_from(Zuorest::TooManyRequestsError) do |error|
    T.bind(self, UpdateZuoraAccountInformationJob)

    zuora_rate_limit_handler(self, error)
  end

  sig { params(zuora_account_id: String, contact_id: T.nilable(Integer)).void }
  def perform(zuora_account_id:, contact_id:)
    contact = Billing::Contact.find_by(id: contact_id)
    return unless contact
    # Zuora requires a first and last name for contact objects but we
    # only have an entity name for entity owned accounts
    first_name = contact.first_name.presence || contact.entity_name
    last_name = contact.last_name.presence || contact.entity_name

    zuora_contact = Billing::Zuora::Account::Contact.new(
      first_name: first_name.to_s,
      last_name: last_name.to_s,
      address1: contact.address1.to_s,
      address2: contact.address2.to_s,
      city: contact.city.to_s,
      state: contact.region.to_s,
      zip_code: contact.postal_code.to_s,
      country: contact.country_code.to_s
    )

    customer_has_shipping_contact = contact.shipping? || T.must(contact.customer).shipping_contact.present?

    request =
      if contact.billing?
        if customer_has_shipping_contact
          Billing::Zuora::Account::UpdateAccountRequest.new(bill_to_contact: zuora_contact)
        else
          Billing::Zuora::Account::UpdateAccountRequest.new(bill_to_contact: zuora_contact, sold_to_contact: zuora_contact)
        end
      else
        Billing::Zuora::Account::UpdateAccountRequest.new(sold_to_contact: zuora_contact)
      end

    result = Billing::Zuora::Account.update(zuora_account_id, request)
    unless result.success?
      zuora_response = result.zuora_result
      GitHub.logger.error(
        "Zuora account update failed",
        "gh.billing.zuora.response.request_id": zuora_response["requestId"],
        "gh.billing.zuora.response.process_id": zuora_response["processId"],
        "gh.billing.zuora.response.reasons": zuora_response["reasons"],
        "gh.billing.zuora.response.success": zuora_response["success"],
      )
    end
  end
end
