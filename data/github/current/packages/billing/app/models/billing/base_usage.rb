# typed: true
# frozen_string_literal: true

class Billing::BaseUsage

  sig do
    params(
      billable_owner: Billing::Types::Account,
      owner: T.nilable(User),
      starts_at: T.untyped,
      shared_usage: T.untyped
    ).void
  end
  def initialize(billable_owner, owner: nil, starts_at: nil, shared_usage: nil)
    @billable_owner = billable_owner
    @plan = billable_owner.plan
    @owner = owner
    @starts_at = starts_at || billable_owner.current_metered_billing_cycle_starts_at
    @shared_usage = shared_usage
    @error = nil
    @shared_usage = shared_usage

    @client_wrapper = Billing::Api::ClientWrapper.new(billable_owner: billable_owner, owner: owner)
  end

  def self.shared_accounts_usage(billable_owner, products:)
    instance = new(billable_owner)
    instance.list_accounts_api_call(products: products)
  end

  sig { returns(T::Boolean) }
  def has_error?
    @error.present?
  end

  def list_accounts_api_call(products:)
    return shared_usage if shared_usage.present?

    client_wrapper.list_account_usage(starts_at, product_names: products)
  end

  def self.owner_and_billable_owner_from(account)
    billable_owner = account.billable_owner
    owner = (billable_owner == account) ? nil : account
    [owner, billable_owner]
  end
  private_class_method :owner_and_billable_owner_from

  sig { params(account: Billing::Types::Account, starts_at: T.untyped).returns(T.untyped) }
  def self.shared_products_usage(account, starts_at: nil)
    owner, billable_owner = owner_and_billable_owner_from(account)
    instance = new(billable_owner, owner: owner, starts_at: starts_at)
    instance.list_products_api_call(products: %w[actions packages shared_storage])
  end

  def usage_quotes_api_call(proposed_usage)
    metered_cycle_starts_at = Google::Protobuf::Timestamp.new(seconds: starts_at.to_i)

    client_wrapper.calculate_usage_quotes(proposed_usage, metered_cycle_starts_at)
  end

  def list_products_api_call(products:)
    return @shared_usage if @shared_usage.present?

    client_wrapper.list_product_usage(starts_at, product_names: products)
  end

  private

  def error_response?(response)
    return unless response.is_a?(Billing::Api::ClientWrapper::BillingClientError)

    @error = response
  end

  def aggregate_by_sku_usage(products_usage, product:)
    sku_usage = Hash.new do |hash, key|
      hash[key] = { effective_quantity: 0, billable_quantity: 0, estimated_cost: 0 }
    end

    selected_product_usage = products_usage.select do |product_usage|
      product_usage[:product][:name].include?(product)
    end

    selected_product_usage.each do |product_usage|
      sku_name = product_usage[:product_sku][:name]

      sku_usage[sku_name][:effective_quantity] += product_usage[:usage][:effective_quantity] || 0
      sku_usage[sku_name][:billable_quantity] += product_usage[:usage][:billable_quantity] || 0
      sku_usage[sku_name][:estimated_cost] += product_usage[:usage][:estimated_cost][:subunits] || 0
    end

    sku_usage
  end

  attr_reader :billable_owner, :plan, :owner, :client_wrapper, :error, :starts_at, :shared_usage
end
