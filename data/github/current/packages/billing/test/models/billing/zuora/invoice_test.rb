# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Zuora::InvoiceTest < GitHub::BillingTestCase
  include DogstatsTestHelpers
  include GitHub::ZuoraTestHelper

  context "when the invoice is not found" do
    test "raises a ResourceNotFound error and adds context to Failbot" do
      fake_response = {
        success: false,
        processId: "BEB2786E9D09BA83",
        reasons: [{
          code: 50000040, message: "Cannot find entity by key: 'INV0002370'."
        }],
        requestId: "ab530963-22ed-4c2f-9946-34efe58705c7"
      }.with_indifferent_access
      request = stub_request(:get, "https://rest.apisandbox.zuora.com/v1/invoices/not_found_id")
        .to_return(body: fake_response.to_json, status: 200,  headers: { content_type: "application/json" })

      Failbot.context.clear

      invoice = ::Billing::Zuora::Invoice.new("not_found_id")

      assert_raises Billing::Zuora::ResourceNotFoundError do
        # trigger the request
        invoice.id
      end

      assert_requested(request)
      assert_equal fake_response, Failbot.squash_contexts(Failbot.context)["gh.billing.zuora.result"]
    end
  end

  context "#cancelled?" do
    test "returns true for a cancelled invoice" do
      with_live_zuora("zuora/invoice_test/canceled_status_invoice_check") do
        response = GitHub.zuorest_client.query_action(
          queryString: "select Id from Invoice where Status = 'Canceled'",
        )

        zuora_invoice = ::Billing::Zuora::Invoice.new(response["records"].first["Id"])

        assert zuora_invoice.cancelled?, "expected invoice to be cancelled but was #{zuora_invoice.status}"
      end
    end
  end

  context ".open_invoices_for_account" do
    test "returns all open invoices" do
      with_live_zuora("zuora/open_invoices_for_account", match_requests_on: [:method, :uri, :body]) do
        zuora_account_id = "8ad087d28b8f8757018b91d9f9af7781"
        invoice_ids = %w(8ad087d28b8f8757018b91dc204a1570 8ad097da90c4bc5d0190e4da92971e80)

        invoices = Billing::Zuora::Invoice.open_invoices_for_account(zuora_account_id)

        assert_equal 2, invoices.length

        invoice = T.must(invoices.pop)
        assert_instance_of ::Billing::Zuora::Invoice, invoice
        assert_includes invoice_ids, invoice.id
        assert invoice.balance > 0

        invoice = T.must(invoices.pop)
        assert_instance_of ::Billing::Zuora::Invoice, invoice
        assert_includes invoice_ids, invoice.id
        assert invoice.balance > 0
      end
    end

    test "returns opens invoices that are posted when posted_only is true" do
      with_live_zuora("zuora/open_invoices_for_account", match_requests_on: [:method, :uri, :body]) do
        zuora_account_id = "8ad087d28b8f8757018b91d9f9af7781"
        invoice_id = "8ad087d28b8f8757018b91dc204a1570"

        invoices = Billing::Zuora::Invoice.open_invoices_for_account(zuora_account_id, posted_only: true)

        assert_equal 1, invoices.length

        invoice = T.must(invoices.pop)
        assert_instance_of ::Billing::Zuora::Invoice, invoice
        assert_equal invoice_id, invoice.id
        assert invoice.balance > 0
      end
    end
  end

  context ".invoices_for_transaction" do
    test "returns invoice IDs for a given transaction" do
      with_live_zuora("zuora/successful_zero_out") do
        zuora_transaction_id = "2c92c0fb62943e2c01629c87ddb30c2e"
        invoice_id = "2c92c0fb62943e2c01629c87dbed0c1c"

        invoices = Billing::Zuora::Invoice.invoices_for_transaction(zuora_transaction_id)

        assert_equal 1, invoices.length

        invoice = T.must(invoices.pop)
        assert_instance_of ::Billing::Zuora::Invoice, invoice
        assert_equal invoice_id, invoice.id
      end
    end
  end

  context ".invoices_for_subscription" do
    test "returns invoice IDs for a given subscription" do
      with_live_zuora("zuora/open_invoices_for_subscription") do
        zuora_subscription_number = "A-S00004667"
        invoice_id = "2c92c0fa62942c5e0162968ae90c40bb"

        invoices = Billing::Zuora::Invoice.invoices_for_subscription(zuora_subscription_number)

        assert_equal 1, invoices.length

        invoice = T.must(invoices.pop)
        assert_instance_of ::Billing::Zuora::Invoice, invoice
        assert_equal invoice_id, invoice.id
      end
    end

    test "doesn't return duplicate invoices" do
      synchronize_github_products_to_zuora

      with_live_zuora("zuora/multiple_invoice_items_for_subscription") do
        org = create :business_plus_organization
        zuora_successful_customer_account_creation(org)
        org.reload

        plan_subscription = org.plan_subscription
        plan_subscription.synchronize

        zuora_subscription_number = org.plan_subscription.zuora_subscription_number
        invoices = Billing::Zuora::Invoice.invoices_for_subscription(zuora_subscription_number)
        unique_invoices = invoices.map(&:id).uniq
        assert_equal invoices.length, unique_invoices.length
      end
    end
  end

  context ".invoices_for_account" do
    test "returns invoices for a given zuora account id" do
      with_live_zuora("zuora/invoices_for_account") do
        account_id = "2c92c0fa6b26b25a016b447ee33455b6"

        invoices = Billing::Zuora::Invoice.invoices_for_account(account_id)

        assert_equal 2, invoices.length

        invoice = T.must(invoices.pop)
        assert_instance_of ::Billing::Zuora::Invoice, invoice
        assert_equal "2c92c0fb6b26bfce016b4489f8d1396b", invoice.id
        assert_equal "INV00006849", invoice.number
        assert_equal 5, invoice.amount
        assert_equal "2019-06-10", invoice.invoice_date
        assert_equal "2019-06-10", invoice.due_date
        assert_equal 0, invoice.balance

        invoice = T.must(invoices.pop)
        assert_instance_of ::Billing::Zuora::Invoice, invoice
        assert_equal "2c92c0fb6c2d53cb016c45cf88741d5e", invoice.id
        assert_equal "INV00006965", invoice.number
        assert_equal 10.98, invoice.amount
        assert_equal "2019-07-30", invoice.invoice_date
        assert_equal "2019-07-30", invoice.due_date
        assert_equal 0, invoice.balance
      end
    end

    test "returns an empty array when there's an error" do
      with_live_zuora("zuora/zuora_invoices_for_unknown_account") do
        assert_empty Billing::Zuora::Invoice.invoices_for_account("not_real")
      end
    end
  end

  context ".record_metrics" do
    test "records negative invoice metrics" do
      Billing::Zuora::Invoice.record_metrics(
        balance_in_cents: -100,
        calling_class: "caller"
      )
      assert_dogstats_increment("zuora.invoices",
        tags: ["balance:negative", "class:caller"])
      assert_dogstats_count_value(100, "zuora.invoices.balance_in_cents",
        tags: ["balance:negative", "class:caller"]
      )
    end

    test "records positive invoice metrics" do
      Billing::Zuora::Invoice.record_metrics(
        balance_in_cents: 100,
        calling_class: "caller"
      )
      assert_dogstats_increment("zuora.invoices",
        tags: ["balance:positive", "class:caller"])
    end

    test "record zero-balance invoice metrics" do
      Billing::Zuora::Invoice.record_metrics(
        balance_in_cents: 0,
        calling_class: "caller"
      )
      assert_dogstats_increment("zuora.invoices",
        tags: ["balance:zero", "class:caller"])
    end
  end

  context "#payment_status" do
    test "paid invoice" do
      invoice = build(:zuora_invoice, :paid)
      assert_equal "Paid", invoice.payment_status
    end

    test "past due invoice" do
      invoice = build(:zuora_invoice, :unpaid, :past_due)
      assert_equal "Payment Overdue", invoice.payment_status
    end

    test "unpaid invoice" do
      invoice = build(:zuora_invoice, :unpaid)
      assert_equal "Invoiced", invoice.payment_status
    end

    test "draft invoice" do
      invoice = build(:zuora_invoice, :draft)
      assert_equal "Draft", invoice.payment_status
    end
  end

  context "#past_due?" do
    test "for a past due invoice" do
      as_of = Date.new(2019, 1, 1)
      invoice = build(:zuora_invoice, dueDate: (as_of - 1.day).to_s)

      assert invoice.past_due?(as_of: as_of), "Expected invoice to be past due"
    end

    test "for a current invoice" do
      as_of = Date.new(2019, 1, 1)
      invoice = build(:zuora_invoice, dueDate: as_of.to_s)

      refute invoice.past_due?(as_of: as_of), "Expected invoice not to be past due"
    end
  end

  context "#suppress_from_customer_view?" do
    test "suppressed" do
      invoice = build(:zuora_invoice, :suppress_from_customer_view)

      assert_predicate invoice, :suppress_from_customer_view?
    end

    test "not suppressed" do
      invoice = build(:zuora_invoice)

      refute_predicate invoice, :suppress_from_customer_view?
    end
  end

  context "#formatted_invoice_date" do
    test "valid date" do
      as_of = Date.new(2020, 3, 1)
      invoice = build(:zuora_invoice, invoiceDate: as_of.to_s)

      assert_equal "2020/03/01", invoice.formatted_invoice_date
    end

    test "invalid date" do
      invoice = build(:zuora_invoice, invoiceDate: "invaliddatestring")
      assert_equal "N/A", invoice.formatted_invoice_date
    end
  end

  context "#credit_balance_adjustment_amount" do
    test "returns the value of creditBalanceAdjustmentAmount" do
      invoice = build(:zuora_invoice, creditBalanceAdjustmentAmount: 42)
      assert_equal 42, invoice.credit_balance_adjustment_amount
    end
  end

  test "data attributes" do
    with_live_zuora("zuora/zuora_invoice") do
      invoice = Billing::Zuora::Invoice.new("2c92c0fb62f80f120162f8dd9ad9432a")

      assert_equal "2018-04-24", invoice.invoice_date
      assert_equal "2018-04-24", invoice.due_on
      assert_equal(-325.83, invoice.amount)
      assert_equal(0.0, invoice.balance)
      assert_equal "Posted", invoice.status
      assert_equal "INV00002862", invoice.number
    end
  end

  context "#invoice_items" do
    test "returns an array of Billing::Zuora::InvoiceItems" do
      # match_on_request_body is required since action/query calls are all the same except for the Body
      with_live_zuora("zuora/invoice_with_invoice_items", match_requests_on: [:body]) do
        invoice = Billing::Zuora::Invoice.new("2c92c0fb62f80f120162f8dd9ad9432a")
        assert_instance_of Array, invoice.invoice_items

        invoice_item = invoice.invoice_items
        invoice_item.each do |invoice_item|
          assert_instance_of Billing::Zuora::InvoiceItem, invoice_item
        end
      end
    end

    test "can resolve subscribables" do
      invoice_id = "fake_invoice_id"
      mock_zuora_invoice_query(invoice_id)
      mock_zuora_rpc_query(expected_calls: 1)

      invoice = Billing::Zuora::Invoice.new(invoice_id)
      invoice_items = invoice.invoice_items
      assert_instance_of Array, invoice_items

      assert_equal 4, invoice_items.count
      assert_equal 2, invoice_items.count { |item| item.charge_amount.positive? }

      invoice_items.each do |invoice_item|
        invoice_item = T.cast(invoice_item, Billing::Zuora::SubscribableInvoiceItem)
        assert_instance_of SponsorsTier, invoice_item.subscribable
      end
    end

    # see https://github.com/github/sponsors/issues/4229
    test "can loop Zuora calls to resolve subscribables over the ZOQL WHERE clause limit" do
      Billing::Zuora::Invoice.stub_const(:ZOQL_QUERY_WHERE_CLAUSE_LIMIT, 1) do
        invoice_id = "fake_invoice_id"
        mock_zuora_invoice_query(invoice_id)
        # there are 4 invoice items, but we stub the RPC limit to 1, so we expect 4 calls
        mock_zuora_rpc_query(expected_calls: 4)

        invoice = Billing::Zuora::Invoice.new(invoice_id)
        invoice_items = invoice.invoice_items
        assert_instance_of Array, invoice_items

        assert_equal 4, invoice_items.count
        assert_equal 2, invoice_items.count { |item| item.charge_amount.positive? }

        invoice_items.each do |invoice_item|
          invoice_item = T.cast(invoice_item, Billing::Zuora::SubscribableInvoiceItem)
          assert_instance_of SponsorsTier, invoice_item.subscribable
        end
      end
    end

    # see https://github.com/github/sponsors/issues/4747
    test "makes no queries for marketplace items if only tracked sponsorship on invoice" do
      invoice_id = "fake_invoice_id"

      # this invoice represents only tracked sponsorship items
      mock_zuora_invoice_query(invoice_id)
      mock_zuora_rpc_query(expected_calls: 1)

      invoice = Billing::Zuora::Invoice.new(invoice_id)
      assert_query_count_per_table({ product_uuids: 0 }) do
        invoice.invoice_items
      end
    end
  end

  def mock_zuora_invoice_query(invoice_id)
    GitHub.zuorest_client
      .expects(:get_invoice_invoice_items)
      .with(invoice_id, page: 1, page_size: 40)
      .returns({
        "invoiceItems" => [{
          "chargeAmount" => 0.52,
          "chargeName" => "sponsors-user-129: Recurring monthly",
          "serviceEndDate" => "2022-09-28",
          "id" => "8ad0823f83362d250183373226517722",
          "subscriptionId" => "8ad0823f83362d2501833732252476e5",
          "serviceStartDate" => "2022-09-13",
          "unitPrice" => 1.0,
          "subscriptionName" => "A-S00097413",
          "chargeId" => "8ad0823f83362d2501833732249b76a7",
          "quantity" => 1.0,
        },
        {
          "chargeAmount" => 0.0,
          "chargeName" => "sponsors-user-129: Recurring monthly fee",
          "serviceEndDate" => "2022-09-28",
          "id" => "8ad0823f83362d250183373226517723",
          "subscriptionId" => "8ad0823f83362d2501833732252476e5",
          "serviceStartDate" => "2022-09-13",
          "unitPrice" => 0.0,
          "subscriptionName" => "A-S00097413",
          "chargeId" => "8ad0823f83362d2501833732249b76a8",
          "quantity" => 1.0
        },
        {
          "chargeAmount" => 0.52,
          "chargeName" => "sponsors-user-162: Recurring monthly",
          "serviceEndDate" => "2022-09-28",
          "id" => "8ad0823f83362d250183373226527724",
          "subscriptionId" => "8ad0823f83362d2501833732252476e5",
          "serviceStartDate" => "2022-09-13",
          "unitPrice" => 1.0,
          "subscriptionName" => "A-S00097413",
          "chargeId" => "8ad0823f83362d250183373224e176b7",
          "quantity" => 1.0
        },
        {
          "chargeAmount" => 0.0,
          "chargeName" => "sponsors-user-162: Recurring monthly fee",
          "serviceEndDate" => "2022-09-28",
          "id" => "8ad0823f83362d250183373226527725",
          "subscriptionId" => "8ad0823f83362d2501833732252476e5",
          "serviceStartDate" => "2022-09-13",
          "unitPrice" => 0.0,
          "subscriptionName" => "A-S00097413",
          "chargeId" => "8ad0823f83362d250183373224e176b8",
          "quantity" => 1.0
        }],
        "success" => true,
      })
  end

  def mock_zuora_rpc_query(expected_calls:)
    sponsors_tier1, sponsors_tier2 = create_pair(:sponsors_tier, :published)
    # rpc_id => tracking_id
    # N.B. this is tightly coupled to `mock_zuora_invoice_query` as the rpc ids need to align
    subscribable_mapping = {
      "8ad0823f83362d2501833732249b76a7" => sponsors_tier1.zuora_tracking_id,
      "8ad0823f83362d2501833732249b76a8" => sponsors_tier1.zuora_tracking_id,
      "8ad0823f83362d250183373224e176b7" => sponsors_tier2.zuora_tracking_id,
      "8ad0823f83362d250183373224e176b8" => sponsors_tier2.zuora_tracking_id,
    }
    calls_mocked = 0
    rpc_ids = subscribable_mapping.keys
    rpc_ids.each_slice(Billing::Zuora::Invoice::ZOQL_QUERY_WHERE_CLAUSE_LIMIT).each do |rpc_ids_slice|
      tracking_field = Billing::Subscribable::ZUORA_TRACKING_FIELD
      where_clause = rpc_ids_slice.map { |id| "Id = '#{id}'" }.join(" OR ")
      query = "SELECT Id, #{tracking_field}, ProductRatePlanChargeId FROM RatePlanCharge WHERE #{where_clause}"
      calls_mocked += 1
      GitHub.zuorest_client.expects(:query_action)
        .with(queryString: query)
        .returns(
          {
            "records" => rpc_ids_slice.map { |rpc_id| { "Id" => rpc_id, tracking_field => subscribable_mapping[rpc_id], "ProductRatePlanChargeId" => "unused" } },
            "done" => true,
            "size" => rpc_ids_slice.size
          }
        )
    end
    assert_equal expected_calls, calls_mocked, "Expected to mock #{expected_calls} calls to Zuora, but #{calls_mocked} were mocked"
  end
end
