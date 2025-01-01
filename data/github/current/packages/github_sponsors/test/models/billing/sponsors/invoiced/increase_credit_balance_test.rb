# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Sponsors::Invoiced::IncreaseCreditBalanceTest < GitHub::TestCase
  include GitHub::ZuoraTestHelper
  include AuditLog::IntegrationTestHelpers
  # From `test/fixtures/vcr_cassettes/zuora/add_credit_balance.yml`
  # The Zuora account ID for "sponsoring-zuora-user" in the Zuora sandbox environment
  LIVE_ZUORA_SPONSOR_ID = "2c92c0fb7a5b3ac8017a5b9dd1a57e2e"

  fixtures do
    @staff = create(:staff_admin_user)
    @sponsors_invoiced_org = create(:invoiced_organization, :sponsors_invoiced)
    @sponsors_customer = @sponsors_invoiced_org.sponsors_customer
  end

  test "adds to a credit balance" do
    @sponsors_customer.update!(zuora_account_id: LIVE_ZUORA_SPONSOR_ID)
    amount = Billing::Money.parse("$1.00")

    with_live_zuora("zuora/add_credit_balance") do
      result = Billing::Sponsors::Invoiced::IncreaseCreditBalance.perform(
        actor: @staff,
        sponsor: @sponsors_invoiced_org,
        amount: amount,
        comment: "test comment",
        reference_id: "test-reference-id",
      )

      assert_predicate result, :success?
    end
  end

  test "creates a guarded staff actor audit log entry" do
    @sponsors_customer.update!(zuora_account_id: LIVE_ZUORA_SPONSOR_ID)
    amount = Billing::Money.parse("$1.00")
    comment = "test comment"
    reference_id = "test-reference-id"

    with_live_zuora("zuora/add_credit_balance") do
      events = assert_performed_audit_entries(count: 1, only: "sponsors.credit_balance_increase") do
        result = Billing::Sponsors::Invoiced::IncreaseCreditBalance.perform(
          actor: @staff,
          sponsor: @sponsors_invoiced_org,
          amount: amount,
          comment: "test comment",
          reference_id: "test-reference-id",
        )

        assert_predicate result, :success?
      end

      expected_payload = {
        actor: "github-staff",
        staff_actor: @staff.login,
        action: "sponsors.credit_balance_increase",
        result: "Success",
        amount_in_cents: 100,
        comment: comment,
        reference_id: reference_id,
        payment_id: "8ad09fc28234561a0182368c04102223",
        operation_type: "create",
        org: @sponsors_invoiced_org.login,
        org_id: @sponsors_invoiced_org.id,
      }

      assert_subset_hash expected_payload, events.first
    end
  end

  test "creates audit log entry even when credit balance increase fails" do
    @sponsors_customer.update!(zuora_account_id: "invalid_account_id")
    amount = Billing::Money.parse("$1.00")
    comment = "test comment"
    reference_id = "test-reference-id"

    with_live_zuora("zuora/add_credit_balance_invalid_account_id") do
      events = assert_performed_audit_entries(count: 1, only: "sponsors.credit_balance_increase") do
        result = Billing::Sponsors::Invoiced::IncreaseCreditBalance.perform(
          actor: @staff,
          sponsor: @sponsors_invoiced_org,
          amount: amount,
          comment: "test comment",
          reference_id: "test-reference-id",
        )

        assert_predicate result, :failed?
      end

      expected_payload = {
        actor: "github-staff",
        staff_actor: @staff.login,
        action: "sponsors.credit_balance_increase",
        result: "Error INVALID_VALUE: Invalid value for field AccountId: invalid_account_id",
        amount_in_cents: 100,
        comment: comment,
        reference_id: reference_id,
        payment_id: nil,
        operation_type: "create",
        org: @sponsors_invoiced_org.login,
        org_id: @sponsors_invoiced_org.id,
      }

      assert_subset_hash expected_payload, events.first
      report = Failbot.reports.find { |report| report["app"] == "github-zuora" }
      assert_equal "Zuorest::HttpError", report["exception_detail"].first["type"]
    end
  end

  context "validations" do
    test "requires invoiced sponsor" do
      org = create(:organization)

      result = Billing::Sponsors::Invoiced::IncreaseCreditBalance.perform(
        actor: @staff,
        sponsor: org,
        amount: Billing::Money.parse("$1.00"),
        comment: "test comment",
        reference_id: "test-reference-id",
      )

      assert_predicate result, :failed?
      assert_equal "Sponsor is not an invoiced sponsor", result.error_message
    end

    test "requires staff actor" do
      non_staff = create(:user)

      result = Billing::Sponsors::Invoiced::IncreaseCreditBalance.perform(
        actor: non_staff,
        sponsor: @sponsors_invoiced_org,
        amount: Billing::Money.parse("$1.00"),
        comment: "test comment",
        reference_id: "test-reference-id",
      )

      assert_predicate result, :failed?
      assert_equal "Actor does not have permission to admin invoiced sponsors", result.error_message
    end

    test "requires amount greater than 0" do
      result = Billing::Sponsors::Invoiced::IncreaseCreditBalance.perform(
        actor: @staff,
        sponsor: @sponsors_invoiced_org,
        amount: Billing::Money.zero,
        comment: "test comment",
        reference_id: "test-reference-id",
      )

      assert_predicate result, :failed?
      assert_equal "Amount must be greater than 0", result.error_message
    end

    test "requires comment" do
      result = Billing::Sponsors::Invoiced::IncreaseCreditBalance.perform(
        actor: @staff,
        sponsor: @sponsors_invoiced_org,
        amount: Billing::Money.parse("$1.00"),
        comment: "",
        reference_id: "test-reference-id",
      )

      assert_predicate result, :failed?
      assert_equal "Comment can't be blank", result.error_message
    end

    test "requires reference_id" do
      result = Billing::Sponsors::Invoiced::IncreaseCreditBalance.perform(
        actor: @staff,
        sponsor: @sponsors_invoiced_org,
        amount: Billing::Money.parse("$1.00"),
        comment: "test comment",
        reference_id: "",
      )

      assert_predicate result, :failed?
      assert_equal "Reference can't be blank", result.error_message
    end

    test "concatenates errors from multiple validations" do
      result = Billing::Sponsors::Invoiced::IncreaseCreditBalance.perform(
        actor: @staff,
        sponsor: @sponsors_invoiced_org,
        amount: Billing::Money.zero,
        comment: "",
        reference_id: "",
      )

      assert_predicate result, :failed?
      assert_equal "Amount must be greater than 0, Comment can't be blank, and Reference can't be blank",
        result.error_message
    end
  end

  context "#via_automation?" do
    test "succeeds when no actor is provided but it is via automation" do
      payment_succeeded_webhook = create(:stripe_webhook, :invoice_payment_succeeded)

      result = Billing::Sponsors::Invoiced::IncreaseCreditBalance.perform(
        actor: nil,
        sponsor: @sponsors_invoiced_org,
        amount: Billing::Money.parse("$1.00"),
        comment: "test comment",
        reference_id: "test-reference-id",
        via_automation: true,
      )

      assert_predicate result, :success?
    end

    test "fails when no actor is provided and it is not via automation" do
      transfer_reversed_webhook = create(:stripe_webhook, :transfer_reversed)

      result = Billing::Sponsors::Invoiced::IncreaseCreditBalance.perform(
        actor: nil,
        sponsor: @sponsors_invoiced_org,
        amount: Billing::Money.parse("$1.00"),
        comment: "test comment",
        reference_id: "test-reference-id",
        via_automation: false,
      )

      assert_predicate result, :failed?
    end

    test "fails when no actor is provided and via automation defaults to false" do
      transfer_reversed_webhook = create(:stripe_webhook, :transfer_reversed)

      result = Billing::Sponsors::Invoiced::IncreaseCreditBalance.perform(
        actor: nil,
        sponsor: @sponsors_invoiced_org,
        amount: Billing::Money.parse("$1.00"),
        comment: "test comment",
        reference_id: "test-reference-id",
      )

      assert_predicate result, :failed?
    end
  end
end if GitHub.sponsors_enabled?
