# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsBillingCreditBalanceInvoiceCollectionJobTest < GitHub::TestCase
  include DogstatsTestHelpers
  include GitHub::ZuoraTestHelper
  include GitHub::LoggerHelper

  fixtures do
    @sponsors_invoiced_org = create(:credit_card_org, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
    @sponsors_invoiced_org.sponsors_customer.update!(
      zuora_account_id: "2c92c0fb7a5b3ac8017a5b9dd1a57e2e",
      zuora_account_number: "A0102171813"
    )
    @sponsors_invoiced_org.sponsors_plan_subscription.update!(
      zuora_subscription_id: "8ad09c4b831325f6018314e9fab812ad",
      zuora_subscription_number: "A-S00097164"
    )
  end

  setup do
    @zuora_account_id = @sponsors_invoiced_org.sponsors_customer.zuora_account_id
    @invoice_id = "8ad09c4b831325f6018314e9fc3512b9"
  end

  test "pays recent invoices via credit balance" do
    stub_summary

    GitHub.zuorest_client.class.any_instance.expects(:create_credit_balance_adjustment)
      .once
      .with(
        {
          "Amount" => 1.0,
          "SourceTransactionId" => "due",
          "Type" => "Decrease"
        }
      )

    GitHub.zuorest_client.class.any_instance.expects(:create_credit_balance_adjustment)
      .once
      .with(
        {
          "Amount" => 4.5,
          "SourceTransactionId" => "future",
          "Type" => "Decrease"
        }
      )

    SponsorsBillingCreditBalanceInvoiceCollectionJob.perform_now(@sponsors_invoiced_org)
  end

  test "updates stats for invoice count and amount" do
    stub_summary

    SponsorsBillingCreditBalanceInvoiceCollectionJob.perform_now(@sponsors_invoiced_org)

    assert_dogstats_increment(2, "sponsors.payment_run.invoice_paid")
    assert_dogstats_count(2, "sponsors.payment_run.amount_in_cents")
    count_event_values = assert_dogstats_count(:at_least_one, "sponsors.payment_run.amount_in_cents").map(&:value)
    expected_amount_in_cents_count_values = [100, 450]
    assert_equal expected_amount_in_cents_count_values, count_event_values
  end

  test "pays single invoice via credit balance" do
    stub_invoice(id: "due", balance: 1.0)

    GitHub.zuorest_client.class.any_instance.expects(:create_credit_balance_adjustment)
      .once
      .with(
        {
          "Amount" => 1.0,
          "SourceTransactionId" => "due",
          "Type" => "Decrease"
        }
      )

    SponsorsBillingCreditBalanceInvoiceCollectionJob.perform_now(@sponsors_invoiced_org, invoice_id: "due")
  end

  test "does nothing if single invoice has already been paid" do
    stub_invoice(id: "paid", balance: 0.0)

    GitHub.zuorest_client.class.any_instance.expects(:create_credit_balance_adjustment).never

    SponsorsBillingCreditBalanceInvoiceCollectionJob.perform_now(@sponsors_invoiced_org, invoice_id: "paid")
  end

  test "does nothing if single invoice is still in draft" do
    invoice_overrides = { "Status" => "Draft" }
    stub_invoice(id: "draft", balance: 1.0, overrides: invoice_overrides)

    GitHub.zuorest_client.class.any_instance.expects(:create_credit_balance_adjustment).never

    SponsorsBillingCreditBalanceInvoiceCollectionJob.perform_now(@sponsors_invoiced_org, invoice_id: "draft")
  end

  test "throws if single invoice is not related to account" do
    invoice_overrides = { "AccountId" => "mismatch" }
    stub_invoice(id: "unrelated", balance: 1.0, overrides: invoice_overrides)

    assert_raises SponsorsBillingCreditBalanceInvoiceCollectionJob::InvoiceAccountMismatchError do
      SponsorsBillingCreditBalanceInvoiceCollectionJob.perform_now(@sponsors_invoiced_org, invoice_id: "unrelated")
    end
  end

  test "cancels the sponsorship if the sponsor has insufficient credit balance" do
    with_live_zuora("zuora/sponsors_billing_invoice_collection_insufficient_balance") do
      sponsorship = create(:sponsorship, sponsor: @sponsors_invoiced_org)
      sub_item = sponsorship.subscription_item
      stub_invoice_items(sponsorships: [sponsorship])

      Billing::Zuora::ZeroOutInvoice.expects(:run)

      SponsorsBillingCreditBalanceInvoiceCollectionJob.perform_now(@sponsors_invoiced_org, invoice_id: @invoice_id)

      sponsorship.reload
      sub_item.reload

      refute_predicate sub_item, :active?
      refute_predicate sponsorship, :active?
    end
  end

  test "cancels only the sponsorships included in the invoice if the sponsor does not have a credit balance" do
    with_live_zuora("zuora/sponsors_billing_invoice_collection_zero_balance") do
      sponsorship = create(:sponsorship, sponsor: @sponsors_invoiced_org)
      uninvoiced_sponsorship = create(:sponsorship, sponsor: @sponsors_invoiced_org)
      sub_item = sponsorship.subscription_item
      stub_invoice_items(sponsorships: [sponsorship])
      @sponsors_invoiced_org.sponsors_customer.update!(
        zuora_account_id: "8ad095dd82e89f9f0182f158fd471ab1",
        zuora_account_number: "A0102176585"
      )
      @sponsors_invoiced_org.sponsors_plan_subscription.update!(
        zuora_subscription_id: "8ad09bce82e89fa10182f15ac56510ff",
        zuora_subscription_number: "A-S00096848"
      )
      @sponsors_invoiced_org.reload

      Billing::Zuora::ZeroOutInvoice.expects(:run)

      SponsorsBillingCreditBalanceInvoiceCollectionJob.perform_now(@sponsors_invoiced_org)

      sponsorship.reload
      uninvoiced_sponsorship.reload

      refute_predicate sponsorship, :active?
      refute_predicate sponsorship.subscription_item, :active?
      assert_predicate uninvoiced_sponsorship, :active?
      assert_predicate uninvoiced_sponsorship.subscription_item, :active?
    end
  end

  test "single sync for multiple cancellations if the sponsor does not have a credit balance" do
    with_live_zuora("zuora/sponsors_billing_invoice_collection_zero_balance") do
      sponsorship1 = create(:sponsorship, sponsor: @sponsors_invoiced_org)
      sponsorship2 = create(:sponsorship, sponsor: @sponsors_invoiced_org)
      stub_invoice_items(sponsorships: [sponsorship1, sponsorship2])
      @sponsors_invoiced_org.sponsors_customer.update!(
        zuora_account_id: "8ad095dd82e89f9f0182f158fd471ab1",
        zuora_account_number: "A0102176585"
      )
      @sponsors_invoiced_org.sponsors_plan_subscription.update!(
        zuora_subscription_id: "8ad09bce82e89fa10182f15ac56510ff",
        zuora_subscription_number: "A-S00096848"
      )
      @sponsors_invoiced_org.reload

      Billing::Zuora::ZeroOutInvoice.expects(:run)

      assert_enqueued_jobs(1, only: SynchronizePlanSubscriptionJob) do
        SponsorsBillingCreditBalanceInvoiceCollectionJob.perform_now(@sponsors_invoiced_org)
      end

      sponsorship1.reload
      sponsorship2.reload

      refute_predicate sponsorship1, :active?
      refute_predicate sponsorship2, :active?
    end
  end

  test "cancels the sponsorship if the sponsor does not have a credit balance" do
    with_live_zuora("zuora/sponsors_billing_invoice_collection_zero_balance") do
      sponsorship = create(:sponsorship, sponsor: @sponsors_invoiced_org)
      sub_item = sponsorship.subscription_item
      stub_invoice_items(sponsorships: [sponsorship])
      @sponsors_invoiced_org.sponsors_customer.update!(
        zuora_account_id: "8ad095dd82e89f9f0182f158fd471ab1",
        zuora_account_number: "A0102176585"
      )
      @sponsors_invoiced_org.sponsors_plan_subscription.update!(
        zuora_subscription_id: "8ad09bce82e89fa10182f15ac56510ff",
        zuora_subscription_number: "A-S00096848"
      )
      @sponsors_invoiced_org.reload

      Billing::Zuora::ZeroOutInvoice.expects(:run)

      SponsorsBillingCreditBalanceInvoiceCollectionJob.perform_now(@sponsors_invoiced_org)

      sponsorship.reload
      sub_item.reload

      refute_predicate sub_item, :active?
      refute_predicate sponsorship, :active?
    end
  end

  test "does not cancel sponsorships for other errors" do
    with_live_zuora("zuora/sponsors_billing_invoice_collection_unknown_error") do
      sub_item = create(:sponsors_subscription_item,
                        plan_subscription: @sponsors_invoiced_org.sponsors_plan_subscription)
      sponsorship = create(:sponsorship, sponsor: @sponsors_invoiced_org, subscription_item: sub_item,
                           sponsorable: sub_item.subscribable.sponsors_listing.sponsorable)
      stub_invoice(id: "unknown", balance: 1.0)

      assert_raises do
        SponsorsBillingCreditBalanceInvoiceCollectionJob.perform_now(@sponsors_invoiced_org, invoice_id: "unknown")
      end

      sponsorship.reload
      sub_item.reload

      assert_predicate sub_item, :active?
      assert_predicate sponsorship, :active?
    end
  end

  test "does nothing for user not invoiced via Sponsors" do
    user = create(:verified_user)

    refute_predicate user, :sponsors_invoiced?, "user should not be invoiced via Sponsors"

    GitHub.zuorest_client.class.any_instance.expects(:create_credit_balance_adjustment).never

    SponsorsBillingCreditBalanceInvoiceCollectionJob.perform_now(user)
  end

  test "does nothing if no user passed" do
    GitHub.zuorest_client.class.any_instance.expects(:create_credit_balance_adjustment).never

    SponsorsBillingCreditBalanceInvoiceCollectionJob.perform_now(nil)
  end

  test "locks queuing up of more than one job for a given invoice" do
    assert_enqueued_jobs 1 do
      SponsorsBillingCreditBalanceInvoiceCollectionJob.perform_later(@sponsors_invoiced_org, invoice_id: "due")
      SponsorsBillingCreditBalanceInvoiceCollectionJob.perform_later(@sponsors_invoiced_org, invoice_id: "due")
    end
  end

  test "locks queuing up of more than one job for all due invoices" do
    assert_enqueued_jobs 1 do
      SponsorsBillingCreditBalanceInvoiceCollectionJob.perform_later(@sponsors_invoiced_org)
      SponsorsBillingCreditBalanceInvoiceCollectionJob.perform_later(@sponsors_invoiced_org)
    end
  end

  test "does not lock queuing up of multiple different invoices" do
    assert_enqueued_jobs 2 do
      SponsorsBillingCreditBalanceInvoiceCollectionJob.perform_later(@sponsors_invoiced_org, invoice_id: "due")
      SponsorsBillingCreditBalanceInvoiceCollectionJob.perform_later(@sponsors_invoiced_org, invoice_id: "paid")
    end
  end

  context "Zuorest::TooManyRequestsError" do
    test "retries when error is seen" do
      GitHub.zuorest_client.class.any_instance.expects(:get_object_invoice)
        .once
        .with("due")
        .raises(Zuorest::TooManyRequestsError.new("", {}, { "RateLimit-Reset" => "600" }))

      freeze_time do
        assert_enqueued_with(job: SponsorsBillingCreditBalanceInvoiceCollectionJob, at: Time.now + 600) do
          SponsorsBillingCreditBalanceInvoiceCollectionJob.perform_now(@sponsors_invoiced_org, invoice_id: "due")
        end
      end
    end

    test "logs retry attempt" do
      GitHub.zuorest_client.class.any_instance.expects(:get_object_invoice)
        .once
        .with("due")
        .raises(Zuorest::TooManyRequestsError.new("", {}, { "RateLimit-Reset" => "600" }))

      expected_log = {
        "code.namespace" => "GitHub::Billing::ZuoraRateLimitHandler",
        "code.function" => "zuora_rate_limit_handler",
        "gh.job.name" => "SponsorsBillingCreditBalanceInvoiceCollectionJob",
        "gh.job.attempts" => 1
      }
      assert_logged(**expected_log) do
        SponsorsBillingCreditBalanceInvoiceCollectionJob.perform_now(@sponsors_invoiced_org, invoice_id: "due")
      end
    end
  end

  context "retryable errors" do
    test "retries gateway timeout error" do
      freeze_time do
        GitHub.zuorest_client.class.any_instance.expects(:get_object_invoice).once.with("due").raises(Zuorest::GatewayTimeoutError.new("", {}))
        assert_enqueued_with(job: SponsorsBillingCreditBalanceInvoiceCollectionJob) do
          SponsorsBillingCreditBalanceInvoiceCollectionJob.perform_now(@sponsors_invoiced_org, invoice_id: "due")
        end
      end
    end

    test "retries lock competition error" do
      freeze_time do
        GitHub.zuorest_client.class.any_instance.expects(:get_object_invoice).once.with("due")
          .raises(::Billing::Zuora::LockCompetitionError.new("", {}))
        assert_enqueued_with(job: SponsorsBillingCreditBalanceInvoiceCollectionJob) do
          SponsorsBillingCreditBalanceInvoiceCollectionJob.perform_now(@sponsors_invoiced_org, invoice_id: "due")
        end
      end
    end

    test "retries internal error" do
      freeze_time do
        GitHub.zuorest_client.class.any_instance.expects(:get_object_invoice).once.with("due").raises(::Billing::Zuora::InternalError.new("", {}))
        assert_enqueued_with(job: SponsorsBillingCreditBalanceInvoiceCollectionJob) do
          SponsorsBillingCreditBalanceInvoiceCollectionJob.perform_now(@sponsors_invoiced_org, invoice_id: "due")
        end
      end
    end
  end


  def stub_invoice(id:, balance:, overrides: {})
    GitHub.zuorest_client.class.any_instance.expects(:get_object_invoice)
      .once
      .with(id)
      .returns(
        {
          "Id" => id,
          "Balance" => balance,
          "AccountId" => @zuora_account_id,
          "Status" => "Posted"
        }.merge(overrides)
      )
  end

  def stub_invoice_items(sponsorships:)
    Billing::Zuora::Invoice.any_instance.expects(:invoice_items).returns(
      sponsorships.map do |sponsorship|
        Billing::Zuora::SubscribableInvoiceItem.new(
          {},
          subscribable: sponsorship.tier,
        )
      end
    )
  end

  def stub_summary
    GitHub.zuorest_client.class.any_instance.expects(:get)
      .once
      .with("/v1/accounts/#{@zuora_account_id}/summary")
      .returns(
        {
          "invoices" => [
            {
              "id" => "due",
              "invoiceNumber" => "INV00016343",
              "invoiceDate" => GitHub::Billing.today.strftime("%F"),
              "dueDate" => GitHub::Billing.today.strftime("%F"),
              "amount" => 1.0,
              "balance" => 1.0,
              "status" => "Posted"
            },
            {
              "id" => "paid",
              "invoiceNumber" => "INV00016342",
              "invoiceDate" => GitHub::Billing.today.strftime("%F"),
              "dueDate" => GitHub::Billing.today.strftime("%F"),
              "amount" => 2.0,
              "balance" => 0.0,
              "status" => "Posted"
            },
            {
              "id" => "draft",
              "invoiceNumber" => "INV00016341",
              "invoiceDate" => GitHub::Billing.today.strftime("%F"),
              "dueDate" => GitHub::Billing.today.strftime("%F"),
              "amount" => 3.0,
              "balance" => 3.0,
              "status" => "Draft"
            },
            {
              "id" => "future",
              "invoiceNumber" => "INV00016340",
              "invoiceDate" => GitHub::Billing.today.strftime("%F"),
              "dueDate" => (GitHub::Billing.today + 1.week).strftime("%F"),
              "amount" => 4.5,
              "balance" => 4.5,
              "status" => "Posted"
            },
          ]
        }
      )
  end
end if GitHub.billing_enabled?
