# typed: strict
# frozen_string_literal: true

# Public: Resolves an Zuora's invoice items to our domain representation.
#
# Resolves Zuora invoice items to our notion of subscribable invoice items which aids
# in generating billing transaction line items, receipts, etc.
#
# Returns an Array[Billing::Zuora::InvoiceItem] (inluding Billing::Zuora::SubscribableInvoiceItem).
class Billing::Zuora::SubscribableInvoiceItemResolver
  extend T::Sig

  include GitHub::Memoizer
  include Scientist

  ZOQL_QUERY_WHERE_CLAUSE_LIMIT = 200

  SUBSCRIPTION_ITEM_FIELD = Billing::Zuora::RatePlanCharge::SUBSCRIPTION_ITEM_ID_FIELD
  SUBSCRIBABLE_FIELD = Billing::Subscribable::ZUORA_TRACKING_FIELD
  PRODUCT_RATE_PLAN_CHARGE_FIELD = "ProductRatePlanChargeId"
  TRACKING_FIELDS = T.let(
    [
      SUBSCRIPTION_ITEM_FIELD,
      SUBSCRIBABLE_FIELD,
      PRODUCT_RATE_PLAN_CHARGE_FIELD,
    ].freeze,
    T::Array[String]
  )

  InvoiceItem = T.type_alias { Billing::Zuora::InvoiceItem }

  class TrackingData < T::Struct
    prop :subscription_item_id, T.nilable(String), name: SUBSCRIPTION_ITEM_FIELD
    prop :subscribable_tracking_id, T.nilable(String), name: SUBSCRIBABLE_FIELD
    prop :product_rate_plan_charge_id, String, name: PRODUCT_RATE_PLAN_CHARGE_FIELD
  end

  sig { params(invoice_id: String).returns(T::Array[InvoiceItem]) }
  def self.call(invoice_id)
    self.new(invoice_id).call
  end

  sig { params(invoice_id: String).void }
  def initialize(invoice_id)
    @invoice_id = invoice_id
  end

  sig { returns T::Array[InvoiceItem] }
  def call
    invoice_items.map { |invoice_item| resolve(invoice_item) }
  end

  private

  sig { returns String }
  attr_reader :invoice_id

  # Private: Query Zuora to generate the initial Array of invoice items to resolve to subscribable invoice items.
  sig { returns T::Array[InvoiceItem] }
  memoize def invoice_items
    Billing::Zuora::InvoiceItem.all(invoice_key: invoice_id)
  end

  # Private: Query Zuora to get tracking data indexed by the invoice item's id.
  sig { returns T::Hash[String, TrackingData] }
  memoize def rate_plan_charge_tracking_data
    records = invoice_items.map(&:rate_plan_charge_id).each_slice(ZOQL_QUERY_WHERE_CLAUSE_LIMIT).inject([]) do |memo, rpc_ids_slice|
      # ID values come from previous ZOQL query and are assumed safe to interpolate
      where_clause = rpc_ids_slice.map { |id| "Id = '#{id}'" }.join(" OR ")
      query = "SELECT Id, #{TRACKING_FIELDS.join(", ")} FROM RatePlanCharge WHERE #{where_clause}"
      response = GitHub.zuorest_client.query_action(queryString: query)
      memo.concat(response["records"])
    end
    records.index_by { |record| record["Id"] }.map { |rpc_id, record| [rpc_id, TrackingData.from_hash(record)] }.to_h
  end

  sig { returns T::Hash[String, Billing::SubscriptionItem] }
  memoize def subscription_item_by_rate_plan_charge_id
    subscription_item_id_by_rpc_id = T.must(search_space[:tracked_subscription_item])
    subscription_items_by_id = Billing::SubscriptionItem.where(
      id: subscription_item_id_by_rpc_id.values
    ).includes(:subscribable, :organization).index_by(&:id)
    subscription_item_id_by_rpc_id.map do |rpc_id, sub_item_id|
      [rpc_id, subscription_items_by_id[sub_item_id]]
    end.to_h
  end

  sig { returns T::Hash[String, SponsorsTier] }
  memoize def tracked_subscribable_by_rate_plan_charge_id
    subscribable_tracking_id_by_rpc_id = T.must(search_space[:tracked_subscribable])
    subscribable_by_subscribable_tracking_id = Billing::Subscribable.from_tracking_ids(
      T.cast(subscribable_tracking_id_by_rpc_id.values, T::Array[String])
    )

    subscribable_tracking_id_by_rpc_id.map do |rpc_id, sub_tracking_id|
      [rpc_id, T.cast(subscribable_by_subscribable_tracking_id[sub_tracking_id.to_s], SponsorsTier)]
    end.to_h
  end

  sig { returns(T::Hash[String, T.nilable(Marketplace::ListingPlan)]) }
  memoize def matching_subscribable_by_rate_plan_charge_id
    product_rate_plan_charge_id_by_rpc_id = T.must(search_space[:matching_subscribable])
    subscribable_by_product_rate_plan_charge_id = Billing::Subscribable.from_product_rpc_ids(
      T.cast(product_rate_plan_charge_id_by_rpc_id.values, T::Array[String])
    )
    product_rate_plan_charge_id_by_rpc_id.map do |rpc_id, product_rate_plan_charge_id|
      [
        rpc_id,
        T.cast(
          subscribable_by_product_rate_plan_charge_id[product_rate_plan_charge_id.to_s],
          T.nilable(Marketplace::ListingPlan)
        )
      ]
    end.to_h
  end

  # Private: Use the fact that resolution is hierarchal to limit querying.
  #
  # Different types of tracking provide different fidelity, so if e.g. an invoice item
  # includes a custom field to track its subscription item, we don't need to attempt to
  # resolve it via subscribable tracking or product rate plan charge matching.
  #
  # The hierarchy should remain consistent with #resolve which is currently
  #
  # subscription item tracking -> subscribable tracking -> product rate plan charge matching
  #
  # Returns a Hash mapping the strategy to a stragegy-specific Hash mapping rate plan charges to their tracking data.
  sig { returns T::Hash[Symbol, T::Hash[String, T.any(String, Integer)]] }
  memoize def search_space
    initial_search_space = {
      tracked_subscription_item: {},
      tracked_subscribable: {},
      matching_subscribable: {},
    }
    rate_plan_charge_tracking_data.each_with_object(initial_search_space) do |(rpc_id, tracking_data), memo|
      case
      when tracking_data.subscription_item_id.present?
        memo[:tracked_subscription_item][rpc_id] = tracking_data.subscription_item_id.to_i
      when tracking_data.subscribable_tracking_id.present?
        memo[:tracked_subscribable][rpc_id] = tracking_data.subscribable_tracking_id
      else
        memo[:matching_subscribable][rpc_id] = tracking_data.product_rate_plan_charge_id
      end
    end
  end

  # Private: Attempt to resolve invoice items to subscribable invoice items.
  #
  # Returns a subscribable invoice item using the first matching strategy, otherwise returning the original
  # invoice item if no matching strategy is successful.
  sig { params(invoice_item: InvoiceItem).returns(InvoiceItem) }
  def resolve(invoice_item)
    case
    when match = tracked_subscription_item(invoice_item)
      match
    when match = tracked_subscribable(invoice_item)
      match
    when match = matching_product_rate_plan_charge(invoice_item)
      match
    else
      invoice_item
    end
  end

  sig { params(invoice_item: InvoiceItem).returns(T.nilable(InvoiceItem)) }
  def tracked_subscription_item(invoice_item)
    rpc_id = invoice_item.rate_plan_charge_id
    sub_item = subscription_item_by_rate_plan_charge_id[rpc_id]
    if sub_item
      invoice_item.as_subscribable_invoice_item(subscribable: sub_item.subscribable, subscription_item: sub_item)
    end
  end

  sig { params(invoice_item: InvoiceItem).returns(T.nilable(InvoiceItem)) }
  def tracked_subscribable(invoice_item)
    rpc_id = invoice_item.rate_plan_charge_id
    subscribable = tracked_subscribable_by_rate_plan_charge_id[rpc_id]
    if subscribable
      invoice_item.as_subscribable_invoice_item(subscribable: subscribable)
    end
  end

  sig { params(invoice_item: InvoiceItem).returns(T.nilable(InvoiceItem)) }
  def matching_product_rate_plan_charge(invoice_item)
    rpc_id = invoice_item.rate_plan_charge_id
    subscribable = matching_subscribable_by_rate_plan_charge_id[rpc_id]
    if subscribable
      invoice_item.as_subscribable_invoice_item(subscribable: subscribable)
    end
  end
end
