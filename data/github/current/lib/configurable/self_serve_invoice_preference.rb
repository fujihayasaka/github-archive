# typed: strict
# frozen_string_literal: true

module Configurable
  module SelfServeInvoicePreference
    extend T::Helpers
    requires_ancestor { Configurable }

    SELF_SERVE_INVOICE_ENABLED_KEY = "SELF_SERVE_INVOICE_ENABLED"

    sig { returns(T::Boolean) }
    def self_serve_invoice_enabled?
      T.bind(self, T.any(User, Organization, Business))

      return false unless config.local?(SELF_SERVE_INVOICE_ENABLED_KEY)

      config.enabled?(SELF_SERVE_INVOICE_ENABLED_KEY)
    end

    sig { params(actor: User).returns(T::Boolean) }
    def enable_self_serve_invoice(actor:)
      T.bind(self, T.any(User, Organization, Business))

      billing_zuora_account = Billing::Zuora::Account.find(self.customer&.zuora_account_id)
      if billing_zuora_account.present?
        email_update_successful = update_zuora_account_information(billable_entity: self, zuora_account: billing_zuora_account)
        return false unless email_update_successful
      end
      config.enable(SELF_SERVE_INVOICE_ENABLED_KEY, actor)
      GitHub.dogstats.increment("billing.self_serve_invoice_email_preference.enable")
      true
    end

    sig { params(actor: User).returns(T::Boolean) }
    def disable_self_serve_invoice(actor:)
      T.bind(self, T.any(User, Organization, Business))

      GitHub.dogstats.increment("billing.self_serve_invoice_email_preference.disable")
      config.delete(SELF_SERVE_INVOICE_ENABLED_KEY, actor)
      true
    end

    private

    sig { params(billable_entity: T.any(User, Organization, Business), zuora_account: Billing::Zuora::Account).returns(T::Boolean) }
    def update_zuora_account_information(billable_entity:, zuora_account:)
      billing_email = billable_entity.billing_email
      trade_screening_record = billable_entity.trade_screening_record
      if trade_screening_record.present?
        address_hash = { address1: trade_screening_record.address1, address2: trade_screening_record.address2, city: trade_screening_record.city }
      end

      if zuora_account.work_email.nil? || zuora_account.work_email != billing_email
        bill_to_contact_update_hash = address_hash.present? ? { workEmail: billing_email }.merge(address_hash) : { workEmail: billing_email }
        response = GitHub.zuorest_client.update_account(zuora_account.id, { billToContact: bill_to_contact_update_hash }, { "Content-Type" => "application/json" })
        response = GitHub::Billing::Result.from_zuora(response)
        return response.success?
      end
      true
    rescue Zuorest::HttpError => e
      Failbot.report!(e, app: "github-zuora")
      GitHub.dogstats.increment("billing.self_serve_invoice_preference.update_email_failed")
      false
    end
  end
end
