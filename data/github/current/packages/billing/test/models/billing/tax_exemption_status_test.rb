# typed: true
# frozen_string_literal: true

require "test_helper"

class TaxExemptionStatusTest < GitHub::TestCase
  fixtures do
    @org = create(:organization, :with_tax_exemption_status)
    @customer = @org.customer
    @tax_exemption_status = @customer.tax_exemption_status
  end

  test "creates a TaxExemptionStatus that belongs to a customer" do
    assert_equal @customer.tax_exemption_status.id, @tax_exemption_status.id
  end

  test "creates a TaxExemptionStatus with the status 'approved' by default" do
    assert @tax_exemption_status.approved?
  end

  test "validates the presence of status_reason when rejecting" do
    assert @tax_exemption_status.approved?

    @tax_exemption_status.status = :rejected

    refute @tax_exemption_status.valid?

    @tax_exemption_status.status = :rejected
    @tax_exemption_status.status_reason = "Invalid state"

    assert @tax_exemption_status.valid?
  end

  test "Does not enqueue a SyncZuoraTaxExemptStatusJob if the status has not changed" do
    assert_enqueued_jobs 0, only: SyncZuoraTaxExemptStatusJob do
      assert @tax_exemption_status.approved?

      @tax_exemption_status.approved!
      # Attributes other than status that have changed should enqueue the job
      @tax_exemption_status.update!(certificate_name: "no_taxes.pdf")
      @tax_exemption_status.save!
    end
  end

  test "Enqueues a SyncZuoraTaxExemptStatusJob if the status has changed" do
    assert_enqueued_jobs 1, only: SyncZuoraTaxExemptStatusJob do
      assert @tax_exemption_status.approved?

      @tax_exemption_status.update(status: :rejected, status_reason: "Invalid state")
      assert @tax_exemption_status.rejected?
    end
  end

  context "audit logging" do
    test "audits record creation" do
      events = subscribe "billing.tax_exemption_status_created"
      org = create(:organization, :with_corporate_terms, customer_account_factory: :credit_card_customer_account)
      expected_payload = {
        customer_id: org.customer.id,
        certificate_name_was: nil,
        certificate_name: nil,
        org: org.login,
        org_id: org.id,
        status: "approved",
        zuora_account_id: org.customer.zuora_account_id
      }

      assert_predicate events, :empty?

      org.customer.create_tax_exemption_status!

      refute_predicate events, :empty?
      assert_equal expected_payload, events.last.payload
    end

    test "audits record updates" do
      events = subscribe "billing.tax_exemption_status_updated"
      expected_payload = {
        customer_id: @customer.id,
        certificate_name_was: @tax_exemption_status.certificate_name,
        certificate_name: @tax_exemption_status.certificate_name,
        org: @org.login,
        org_id: @org.id,
        status: "rejected",
        zuora_account_id: @org.customer.zuora_account_id
      }

      assert_predicate @tax_exemption_status, :approved?
      assert_predicate events, :empty?

      @tax_exemption_status.update(status: :rejected, status_reason: "Invalid state")

      refute_predicate events, :empty?
      assert_equal expected_payload, events.last.payload
    end

    test "audit payload includes previous and current certificate name" do
      events = subscribe "billing.tax_exemption_status_updated"
      expected_payload = {
        customer_id: @customer.id,
        certificate_name_was: @tax_exemption_status.certificate_name,
        certificate_name: "no_taxes.pdf",
        org: @org.login,
        org_id: @org.id,
        status: "approved",
        zuora_account_id: @org.customer.zuora_account_id
      }

      assert_predicate events, :empty?

      @tax_exemption_status.update(certificate_name: "no_taxes.pdf")

      refute_predicate events, :empty?
      assert_equal expected_payload, events.pop.payload
      assert_predicate events, :empty?


      @tax_exemption_status.update(certificate_name: "new_cert.pdf")

      refute_predicate events, :empty?
      expected_payload = {
        customer_id: @customer.id,
        certificate_name_was: "no_taxes.pdf",
        certificate_name: "new_cert.pdf",
        org: @org.login,
        org_id: @org.id,
        status: "approved",
        zuora_account_id: @org.customer.zuora_account_id
      }
      assert_equal expected_payload, events.pop.payload
    end
  end
end if GitHub.billing_enabled?
