# typed: true
# frozen_string_literal: true

require "test_helper"

class UpdateZuoraAccountInformationJobTest < GitHub::TestCase
  require "test_helpers/job_test_helper"

  include JobTestHelper
  include GitHub::LoggerHelper

  setup do
    @customer = create(:customer)
    @billing_contact = create(:billing_contact, :billing, customer: @customer)
    @shipping_contact = create(:shipping_contact, customer: @customer)
    @zuora_billing_contact = Billing::Zuora::Account::Contact.new(
      first_name: @billing_contact.first_name.to_s,
      last_name: @billing_contact.last_name.to_s,
      address1: @billing_contact.address1.to_s,
      address2: @billing_contact.address2.to_s,
      city: @billing_contact.city.to_s,
      state: @billing_contact.region.to_s,
      zip_code: @billing_contact.postal_code.to_s,
      country: @billing_contact.country_code.to_s
    )
    @zuora_shipping_contact = Billing::Zuora::Account::Contact.new(
      first_name: @shipping_contact.first_name.to_s,
      last_name: @shipping_contact.last_name.to_s,
      address1: @shipping_contact.address1.to_s,
      address2: @shipping_contact.address2.to_s,
      city: @shipping_contact.city.to_s,
      state: @shipping_contact.region.to_s,
      zip_code: @shipping_contact.postal_code.to_s,
      country: @shipping_contact.country_code.to_s
    )
  end

  test "retries on dirty exit" do
    assert_retry_on_dirty_exit job: UpdateZuoraAccountInformationJob
  end

  test "retries on recoverable exceptions" do
    assert_retry_on_recoverable_exceptions job: UpdateZuoraAccountInformationJob
  end

  test "updates Zuora's 'Bill To' with billing contact information " do
    zuora_account_id = "A00000001"

    update_request = Billing::Zuora::Account::UpdateAccountRequest.new(
      bill_to_contact: @zuora_billing_contact,
      sold_to_contact: nil
    )
    assert @customer.shipping_contact.present?
    Billing::Zuora::Account::Contact.expects(:new).with(
      first_name: @billing_contact.first_name.to_s,
      last_name: @billing_contact.last_name.to_s,
      address1: @billing_contact.address1.to_s,
      address2: @billing_contact.address2.to_s,
      city: @billing_contact.city.to_s,
      state: @billing_contact.region.to_s,
      zip_code: @billing_contact.postal_code.to_s,
      country: @billing_contact.country_code.to_s
    ).returns(@zuora_billing_contact)
    Billing::Zuora::Account::UpdateAccountRequest.expects(:new).with(
      bill_to_contact: @zuora_billing_contact,
    ).returns(update_request)
    Billing::Zuora::Account.expects(:update).with(
      zuora_account_id,
      update_request
    ).returns(GitHub::Billing::Result.success)

    assert_nothing_raised do
      UpdateZuoraAccountInformationJob.perform_now(zuora_account_id: zuora_account_id, contact_id: @billing_contact.id)
    end
  end

  test "updates Zuora 'Sold To' with shipping contact information" do
    zuora_account_id = "A00000001"

    update_request = Billing::Zuora::Account::UpdateAccountRequest.new(
      sold_to_contact: @zuora_shipping_contact
    )
    Billing::Zuora::Account::Contact.expects(:new).with(
      first_name: @shipping_contact.first_name.to_s,
      last_name: @shipping_contact.last_name.to_s,
      address1: @shipping_contact.address1.to_s,
      address2: @shipping_contact.address2.to_s,
      city: @shipping_contact.city.to_s,
      state: @shipping_contact.region.to_s,
      zip_code: @shipping_contact.postal_code.to_s,
      country: @shipping_contact.country_code.to_s
    ).returns(@zuora_shipping_contact)
    Billing::Zuora::Account::UpdateAccountRequest.expects(:new).with(
      sold_to_contact: @zuora_shipping_contact,
    ).returns(update_request)
    Billing::Zuora::Account.expects(:update).with(
      zuora_account_id,
      update_request
    ).returns(GitHub::Billing::Result.success)

    assert_nothing_raised do
      UpdateZuoraAccountInformationJob.perform_now(zuora_account_id: zuora_account_id, contact_id: @shipping_contact.id)
    end
  end

  test "updates both Zuora 'Bill To' and 'Sold To' if the customer has billing information but no shipping information" do
    @customer.shipping_contact.destroy!
    @customer.reload
    zuora_account_id = "A00000001"

    update_request = Billing::Zuora::Account::UpdateAccountRequest.new(
      bill_to_contact: @zuora_billing_contact,
      sold_to_contact: @zuora_billing_contact
    )
    refute @customer.shipping_contact.present?
    Billing::Zuora::Account::Contact.expects(:new).with(
      first_name: @billing_contact.first_name.to_s,
      last_name: @billing_contact.last_name.to_s,
      address1: @billing_contact.address1.to_s,
      address2: @billing_contact.address2.to_s,
      city: @billing_contact.city.to_s,
      state: @billing_contact.region.to_s,
      zip_code: @billing_contact.postal_code.to_s,
      country: @billing_contact.country_code.to_s
    ).returns(@zuora_billing_contact)
    Billing::Zuora::Account::UpdateAccountRequest.expects(:new).with(
      bill_to_contact: @zuora_billing_contact,
      sold_to_contact: @zuora_billing_contact
    ).returns(update_request)
    Billing::Zuora::Account.expects(:update).with(
      zuora_account_id,
      update_request
    ).returns(GitHub::Billing::Result.success)

    assert_nothing_raised do
      UpdateZuoraAccountInformationJob.perform_now(zuora_account_id: zuora_account_id, contact_id: @billing_contact.id)
    end
  end

  test "logs an error when the Zuora account update fails" do
    Billing::Zuora::Account.expects(:update).returns(
      GitHub::Billing::Result.from_zuora({
        "requestId" => "request_id",
        "processId" => "process_id",
        "reasons" => [{ "message" => "reasons" }],
        "success" => false,
      }))

    logged_context = {
      "gh.billing.zuora.response.request_id": "request_id",
      "gh.billing.zuora.response.process_id": "process_id",
      "gh.billing.zuora.response.reasons": [{ "message" => "reasons" }],
      "gh.billing.zuora.response.success": false,
    }
    assert_logged(**logged_context) do
      UpdateZuoraAccountInformationJob.perform_now(zuora_account_id: "account_id", contact_id: @billing_contact.id)
    end
  end
end if GitHub.billing_enabled?
