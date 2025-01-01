# typed: strict
# frozen_string_literal: true

class Billing::ZuoraPaypal
  class Error < StandardError; end

  sig do
    params(
      target_details: T::Hash[Symbol, T.untyped],
      paypal_nonce: T.nilable(String),
      billing_address: T::Hash[Symbol, T.untyped],
      vat_code: T.nilable(String),
      tax_exemption_status: T.nilable(Billing::TaxExemptionStatus)
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def self.create_account(target_details:, paypal_nonce:, billing_address:, vat_code: nil, tax_exemption_status: nil)
    zuora_response = { success: T.let(true, T::Boolean) }

    begin
      account_response = GitHub.zuorest_client.create_object_account({
        AutoPay: false,
        BillCycleDay: target_details[:billed_on],
        BusinessSegment__c: Billing::CreateCustomer::SELF_SERVE_BUSINESS_SEGMENT,
        Batch: Billing::CreateCustomer::SELF_SERVE_BATCH,
        CommunicationProfileId: GitHub.zuora_self_serve_communication_profile_id,
        SynctoNetSuite__NS: "No",
        PaymentTerm: "Due Upon Receipt",
        Currency: "USD",
        Name: target_details[:external_name],
        Status: "Draft",
        TaxExemptStatus: tax_exemption_status&.approved? ? "Yes" : "No",
        TaxExemptCertificateID: tax_exemption_status&.id&.to_s || "N/A",
        APM__c: "True", # See https://knowledgecenter.zuora.com/Zuora_Collect/Zuora_Collections/CA_Advanced_Payment_Manager
      })

      zuora_response[:account_id] = account_response["Id"]

      braintree_response = Braintree::Customer.create({
        id: zuora_response[:account_id],
        first_name: target_details[:external_name],
        custom_fields: target_details.fetch(:bt_fields, {}),
        payment_method_nonce: paypal_nonce,
      })
      unless braintree_response.success?
        Failbot.report(Billing::CreateCustomer::BraintreeCreationError.new("Customer creation failed"), {
          "gh.billing.zuora.account_id": zuora_response[:account_id],
          "gh.billing.braintree.response.message": braintree_response.message
        })
        return { success: false }
      end

      paypal_account = braintree_response.customer.paypal_accounts.first
      zuora_response[:paypal_account] = paypal_account

      response = create_payment_method(
        account_id: zuora_response[:account_id],
        paypal_email: paypal_account.email,
        billing_agreement_id: paypal_account.billing_agreement_id,
      )


      # For some places like the District of Columbia, Zuora expects a specific value
      # that is different from what we use elsewhere. In that case, we'll map to the
      # Zuora value.
      zuora_region =
        case billing_address[:region]
        when "District of Columbia" then "DC"
        else billing_address[:region]
        end

      contact_response = GitHub.zuorest_client.create_contact({
        AccountId: zuora_response[:account_id],
        FirstName: target_details[:external_name],
        LastName: target_details[:external_name],
        PostalCode: billing_address[:postal_code],
        Country: billing_address[:country_code_alpha3],
        State: zuora_region,
      })

      zuora_response[:contact_id] = contact_response["Id"]
      return response unless response[:success]

      zuora_response.merge!(response)

      account_update_response = GitHub.zuorest_client.update_object_account(zuora_response[:account_id], {
        AutoPay: true,
        BillToId: zuora_response[:contact_id],
        SoldToId: zuora_response[:contact_id],
        DefaultPaymentMethodId: zuora_response[:payment_method_id],
        Status: "Active",
        VATId: vat_code,
      })

      account = ::Billing::Zuora::Account.find(zuora_response[:account_id])
      unless account&.active?
        GitHub.logger.info(
          "Account not active after update",
          "code.namespace" => self.class.name,
          "code.function" => "create_account",
          "gh.billing.zuora.update_account.response" => account_update_response,
          "gh.billing.zuora.account.id" => account&.id,
        )
        return { success: false }
      end

      zuora_response[:account_number] = account.number
    rescue Zuorest::HttpError => e
      Failbot.report!(e, app: "github-zuora")
      zuora_response[:success] = false
    end

    zuora_response
  end

  sig do
    params(
      account_id: String,
      paypal_nonce: T.nilable(String),
      paypal_email: T.nilable(String),
      billing_agreement_id: T.nilable(String)
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def self.create_payment_method(account_id:, paypal_nonce: nil, paypal_email: nil, billing_agreement_id: nil)
    zuora_response = { success: T.let(true, T::Boolean) }

    begin
      if paypal_nonce.present?
        response = Braintree::PaymentMethod.create!(
          customer_id: account_id,
          payment_method_nonce: paypal_nonce,
          options: { make_default: true },
        )

        paypal_email = response.email
        billing_agreement_id = response.billing_agreement_id
      end

      GitHub.zuorest_client.update_action({
        "objects": [{
          AutoPay: false,
          PaymentGateway: "Paypal",
          fieldsToNull: ["DefaultPaymentMethodId"],
          Id: account_id,
        }],
        "type": "Account",
      })

      payment_method_response = GitHub.zuorest_client.create_payment_method({
        AccountId: account_id,
        PaypalType: "ExpressCheckout",
        PaypalEmail: paypal_email,
        PaypalBaid: billing_agreement_id,
        Type: "PayPal",
      })
      zuora_response[:payment_method_id] = payment_method_response["Id"]
    rescue Zuorest::HttpError => e
      Failbot.report!(e, "gh.billing.zuora.account.id": account_id, app: "github-zuora")
      zuora_response[:success] = false
    rescue Braintree::BraintreeError => e
      if e.respond_to?(:error_result) && T.unsafe(e).error_result.errors.any? { |error| error.code == "82905" }
        raise Billing::ZuoraPaypal::Error.new \
          "Braintree Customer with Zuora ID required to add a PayPal payment method for #{account_id}"
      end

      Failbot.report(e, "gh.billing.zuora.account.id": account_id)
      zuora_response[:success] = false
    end

    zuora_response
  end
end
