# typed: strict
# frozen_string_literal: true

class UpdateZuoraAccountInformationJob < BillingJob
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

    zuora_contact = Billing::Zuora::Account::Contact.new(
      first_name: contact_first_name(contact:),
      last_name: contact_last_name(contact:),
      address1: contact.address1.to_s,
      address2: contact.address2.to_s,
      city: contact.city.to_s,
      state: contact.region.to_s,
      zip_code: contact.postal_code.to_s,
      country: contact.country_code.to_s
    )

    customer_has_shipping_contact = contact.shipping? || T.must(contact.customer).shipping_contact.persisted?

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

  private

  sig { params(contact: Billing::Contact).returns(String) }
  def contact_first_name(contact:)
    return contact.first_name if contact.first_name.present?
    # Zuora requires a first name for contact objects but we
    # only have an entity name for entity owned accounts
    split_entity_name = contact.entity_name.split(" ")
    split_entity_name.first
  end

  sig { params(contact: Billing::Contact).returns(String) }
  def contact_last_name(contact:)
    return contact.last_name if contact.last_name.present?
    # Zuora requires a last name for contact objects but we
    # only have an entity name for entity owned accounts
    entity_name = contact.entity_name
    split_entity_name = entity_name.split(" ")
    if split_entity_name.size == 1
      contact.entity_name
    else
      split_entity_name[1..-1].to_a.join(" ")
    end
  end
end
