# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Zuora::SubscribableInvoiceItemResolverTest < GitHub::BillingTestCase
  test "returns invoice items if no matches" do
    invoice_id = "INV001"
    raw_invoice_item = mock_raw_invoice_item
    mock_zuora_invoice_queries(invoice_id, invoice_item: raw_invoice_item)

    expected_invoice_items = [Billing::Zuora::InvoiceItem.new(raw_invoice_item)]
    invoice_items = Billing::Zuora::SubscribableInvoiceItemResolver.call(invoice_id)

    assert_equal expected_invoice_items, invoice_items
  end

  test "returns tracked subscription item" do
    invoice_id = "INV001"
    sub_item = create(:billing_subscription_item)
    rate_plan_charge_id = SecureRandom.hex
    raw_invoice_item = mock_raw_invoice_item(
      rate_plan_charge_id: rate_plan_charge_id,
      Subscription_Item_Id__c: sub_item.id.to_s
    )
    mock_zuora_invoice_queries(
      invoice_id,
      invoice_item: raw_invoice_item,
      subscription_item_map: { rate_plan_charge_id => sub_item.id.to_s }
    )

    expected_invoice_item =
      Billing::Zuora::SubscribableInvoiceItem.new(
        raw_invoice_item,
        subscription_item: sub_item
      )
    subscribable_invoice_items = Billing::Zuora::SubscribableInvoiceItemResolver.call(invoice_id)
    assert_equal [expected_invoice_item], subscribable_invoice_items
    assert_equal sub_item, expected_invoice_item.subscription_item
  end

  test "returns tracked subscribable" do
    invoice_id = "INV001"
    sub_item = create(:sponsors_subscription_item)
    subscribable = sub_item.subscribable
    rate_plan_charge_id = SecureRandom.hex
    raw_invoice_item = mock_raw_invoice_item(
      rate_plan_charge_id: rate_plan_charge_id,
      Subscribable_Tracking_Id__c: subscribable.zuora_tracking_id
    )
    mock_zuora_invoice_queries(
      invoice_id,
      invoice_item: raw_invoice_item,
      subscribable_map: { rate_plan_charge_id => subscribable.zuora_tracking_id }
    )

    expected_invoice_item = Billing::Zuora::SubscribableInvoiceItem.new(raw_invoice_item, subscribable: subscribable)
    subscribable_invoice_items = Billing::Zuora::SubscribableInvoiceItemResolver.call(invoice_id)
    assert_equal [expected_invoice_item], subscribable_invoice_items
    assert_equal subscribable, expected_invoice_item.subscribable
  end

  test "returns matching product rate plan charge" do
    invoice_id = "INV001"
    sub_item = create(:billing_subscription_item)
    subscribable = sub_item.subscribable
    subscribable.sync_to_zuora
    rate_plan_charge_id = SecureRandom.hex
    raw_invoice_item = mock_raw_invoice_item(
      rate_plan_charge_id: rate_plan_charge_id,
    )
    product_rate_plan_charge_id = subscribable.product_uuid(:month).charges.first.zuora_product_rate_plan_charge_id
    mock_zuora_invoice_queries(
      invoice_id,
      invoice_item: raw_invoice_item,
      product_rate_plan_charge_map: { rate_plan_charge_id => product_rate_plan_charge_id }
    )
    expected_invoice_item = Billing::Zuora::SubscribableInvoiceItem.new(raw_invoice_item, subscribable: subscribable)
    subscribable_invoice_items = Billing::Zuora::SubscribableInvoiceItemResolver.call(invoice_id)
    assert_equal [expected_invoice_item], subscribable_invoice_items
    assert_equal subscribable, expected_invoice_item.subscribable
  end

  def mock_raw_invoice_item(
    rate_plan_charge_id: SecureRandom.hex,
    **kwargs
  )
    extra_data = kwargs.map { |key, val| [key.to_s, val.to_s] }.to_h

    id = SecureRandom.hex
    charge_name = Faker::Commerce.product_name
    subscription_id = SecureRandom.hex
    subscription_number = SecureRandom.hex
    start_date = GitHub::Billing.today
    end_date = start_date + 1.month
    {
      "id" => id,
      "chargeId" => rate_plan_charge_id,
      "chargeName" => charge_name,
      "chargeAmount" => 0.0,
      "quantity" => 1.0,
      "subscriptionId" => subscription_id,
      "subscriptionName" => subscription_number,
      "unitPrice" => 10.0,
      "serviceStartDate" => start_date.to_s,
      "serviceEndDate" => end_date.to_s
    }.merge(extra_data)
  end

  def mock_zuora_invoice_queries(
    invoice_id,
    invoice_item:,
    expected_rate_plan_charge_query_count: 1,
    subscription_item_map: Hash.new { "" },
    subscribable_map: Hash.new { "" },
    product_rate_plan_charge_map: Hash.new { SecureRandom.hex }
  )

    mock_zuora_invoice_items_query(
      invoice_id,
      invoice_item: invoice_item
    )
    mock_zuora_rate_plan_charge_queries(
      expected_calls: expected_rate_plan_charge_query_count,
      rate_plan_charge_ids: [invoice_item["chargeId"]],
      subscription_item_map: subscription_item_map,
      subscribable_map: subscribable_map,
      product_rate_plan_charge_map: product_rate_plan_charge_map
    )
  end

  def mock_zuora_invoice_items_query(invoice_id, invoice_item:)
    GitHub.zuorest_client.expects(:get_invoice_invoice_items).with(
      invoice_id, page: 1, page_size: 40
    ).returns({
      "invoiceItems" => [invoice_item],
      "success" => true
    })
  end

  def mock_zuora_rate_plan_charge_queries(
    expected_calls:,
    rate_plan_charge_ids:,
    subscription_item_map:,
    subscribable_map:,
    product_rate_plan_charge_map:
  )
    calls_mocked = 0
    rate_plan_charge_ids.each_slice(Billing::Zuora::Invoice::ZOQL_QUERY_WHERE_CLAUSE_LIMIT).each do |rpc_ids_slice|
      where_clause = rpc_ids_slice.map { |id| "Id = '#{id}'" }.join(" OR ")
      query = "SELECT Id, Subscription_Item_Id__c, Subscribable_Tracking_Id__c, ProductRatePlanChargeId "\
        "FROM RatePlanCharge WHERE #{where_clause}"
      calls_mocked += 1
      GitHub.zuorest_client.expects(:query_action)
        .with(queryString: query)
        .returns(
          {
            "records" => rpc_ids_slice.map do |rpc_id|
              {
                "Id" => rpc_id,
                "Subscription_Item_Id__c" => subscription_item_map[rpc_id],
                "Subscribable_Tracking_Id__c" => subscribable_map[rpc_id],
                "ProductRatePlanChargeId" => product_rate_plan_charge_map[rpc_id]
              }
            end,
            "done" => true,
            "size" => rpc_ids_slice.size
          }
        )
    end
    assert_equal expected_calls, calls_mocked, "Expected to mock #{expected_calls} calls to Zuora, but #{calls_mocked} were mocked"
  end
end
