# typed: true
# frozen_string_literal: true
require "scientist"

module Billing
  class UsageChecker

    # Represents detailed information about a given entitlement
    #   name: the entitlement name
    #   consumed_quantity: the quantity of entitlements used
    #   allocated_quantity: the quantity of entitlements allocated at the beginning of the billing cycle, regardless of usage
    #   unit_of_measure: the unit of measure for the consumed_quantity/allocated_quantity ("minutes")
    #   remaining_quantity: the quantity of entitlements remaining that are available
    class EntitlementResult
      attr_reader :name, :consumed_quantity, :allocated_quantity, :unit_of_measure, :remaining_quantity

      include GitHub::Memoizer

      # Represents detailed information about a given entitlement
      # These fields are not raw quantities and have had the multiplier applied
      #   name: the sku name
      #   consumed_quantity: total quantity of entitlements that is multiplied
      #   allocated_quantity: total quantity of allocated entitlements
      #   remaining_quantity: total quantity of entitlements remaining
      def initialize(name:, consumed_quantity:, allocated_quantity:, unit_of_measure:, remaining_quantity:)
        @name = name
        @consumed_quantity = consumed_quantity
        @allocated_quantity = allocated_quantity
        @unit_of_measure = unit_of_measure
        @remaining_quantity = remaining_quantity
      end

      memoize def consumed_percentage
        percent = consumed_quantity / allocated_quantity
        [(percent * 100).to_i, 100].min
      end
    end

    # Represents detailed information about a given sku usage that includes costs
    #   name: the sku name
    #   total_consumed_quantity: total quantity of usage with entitlements multiplied
    #   total_raw_consumed_quantity: total raw quantity of usage
    #   overage_consumed_quantity: total raw quantity of paid usage
    #   entitlement_raw_quantity_consumed: total raw quantity of usage towards entitlements
    #   entitlement_quantity_consumed: total quantity of usage towards entitlements that has been multiplied
    #   sku_multiplier: the multiplier used for entitlements to convert from mins to core mins
    #   estimated_cost: the estimated cost of usage
    #   unit_of_measure: the unit of measure for the consumed_quantity ("minutes")
    #   entitlement: EntitlementResult object associated with the sku
    #   budget_limit: the spending/budget limit associated with this product sku, also known as spending limit.
    #   budgets: Billing::Budget objects associated with the sku
    #   account_consumed_quantity: total quantity of consumed usage for the enterprise owned organization account. Will be nil for non-enterprise accounts.
    #   account_consumed_cost: total cost of consumed usage for the enterprise owned organization account. Will be nil for non-enterprise accounts.
    class UsageResult
      attr_reader :name, :total_consumed_quantity, :total_raw_consumed_quantity, :overage_consumed_quantity, :estimated_cost, :budget_limit, :unit_of_measure, :entitlement, :budgets, :entitlement_raw_quantity_consumed, :entitlement_quantity_consumed, :sku_multiplier, :unit_price, :account_consumed_quantity, :account_consumed_cost

      def initialize(name:, total_consumed_quantity:, total_raw_consumed_quantity:, overage_consumed_quantity:, entitlement_raw_quantity_consumed:, entitlement_quantity_consumed:, estimated_cost:, budget_limit:, unit_of_measure:, entitlement:, budgets:, unit_price:, sku_multiplier:, account_consumed_quantity:, account_consumed_cost:)
        @name = name
        @total_consumed_quantity = total_consumed_quantity
        @total_raw_consumed_quantity = total_raw_consumed_quantity
        @overage_consumed_quantity = overage_consumed_quantity
        @entitlement_raw_quantity_consumed = entitlement_raw_quantity_consumed
        @entitlement_quantity_consumed = entitlement_quantity_consumed
        @sku_multiplier = sku_multiplier
        @estimated_cost = estimated_cost
        @budget_limit = budget_limit
        @unit_of_measure = unit_of_measure
        @entitlement = entitlement
        @budgets = budgets
        @unit_price = unit_price
        @account_consumed_quantity = account_consumed_quantity
        @account_consumed_cost = account_consumed_cost
      end

      def to_h
        {
          total_consumed_quantity: total_consumed_quantity,
          overage_consumed_quantity: overage_consumed_quantity,
          entitlement_quantity_consumed: entitlement_quantity_consumed,
          sku_multiplier: sku_multiplier,
          estimated_cost: estimated_cost,
          budget_limit: budget_limit,
          unit_of_measure: unit_of_measure,
          unit_price: unit_price
        }
      end

      def additional_cost_in_subunits(additional_quantity:)
        entitlement_remaining = entitlement&.remaining_quantity || 0
        adjusted_entitlement_remaining = entitlement_remaining.to_f / sku_multiplier
        adjusted_entitlement_remaining = 0 if adjusted_entitlement_remaining.nan?

        additional_quantity_beyond_entitlement = [additional_quantity.to_f - adjusted_entitlement_remaining, 0].max

        additional_cost_in_subunits = (unit_price * additional_quantity_beyond_entitlement * 100).to_i
      end
    end

    include GitHub::Memoizer
    BILLING_PLATFORM_ONLY_PRODUCTS = %w[ghas ghec git_lfs].freeze

    attr_reader :account, :billable_owner, :product_names, :client, :request_error, :is_enterprise_org

    # UsageChecker uses `get_usage_breakdown` meuse endpoint
    #   Entitlement and usage breakdowns for multiple products can be fetched at one time.
    #   This class provides methods to interact with the response
    #   to answer questions about entitlements, usage, spending/budget limit for a given product/sku in the response.
    # args
    #   :account - The account requesting the check. Can be user, org or enterprise org or enterprise
    #   :product_names - Array of product names to ask meuse for usage breakdowns (["actions", "codespaces"])
    #   :timeout - Time in Seconds to timeout on the meuse billing API call
    def initialize(account:, product_names:, timeout: nil)
      @account = account
      @product_names = if account.customer&.billed_via_billing_platform?
        product_names
      else
        product_names - BILLING_PLATFORM_ONLY_PRODUCTS
      end
      @billable_owner = account.billable_owner
      @is_enterprise_org = account.delegate_billing_to_business? || false
      @client = Billing::Api::ClientWrapper.new(billable_owner: billable_owner, owner: account, timeout: timeout)
      @request_error = false
    end

    # Public: Whether usage should be available based on owners set spending/budget limit and entitlements for a sku
    #
    # args
    #   :sku - String sku name that should be checked to allow usage ("compute_d2")
    # Returns Boolean
    def usage_available?(product:, sku:, additional_quantity: 0)
      usage = usage_for(product: product, sku: sku, account_specific_lookup: false)
      return false unless usage

      entitlement_remaining = usage.entitlement&.remaining_quantity || 0

      return true if entitlement_remaining.positive? && entitlement_remaining >= additional_quantity * usage.sku_multiplier
      return false if billable_owner.metered_services_locked?
      return false if paid_overages_restricted_by_owner_payment_issue?

      additional_cost_in_subunits = usage.additional_cost_in_subunits(additional_quantity:)
      has_budget_remaining?(usage: usage, additional_cost_in_subunits: additional_cost_in_subunits)
    end

    # Public: Detailed information about a given entitlement
    #
    # args
    #   :name - String name entitlement ("Codespaces - Compute")
    #   :id - String id of the entitlement
    # Returns EntitlementResult or nil
    def entitlements_for(name: nil, id: nil)
      raise ArgumentError.new("name or id must be provided") unless name || id

      entitlement = usage_breakdown[:entitlements]&.find do |entitlement|
        entitlement[:name] == name || entitlement[:id] == id
      end

      return unless entitlement

      EntitlementResult.new(
        name: entitlement[:name],
        consumed_quantity: entitlement[:consumed_quantity],
        allocated_quantity: entitlement[:allocated_quantity],
        unit_of_measure: entitlement[:unit_of_measure][:name],
        remaining_quantity: entitlement[:allocated_quantity] - entitlement[:consumed_quantity]
      )
    end

    # Public: Detailed information about a given sku usage that includes costs
    #
    # args
    #   :sku - String name sku ("linux_4_core", "compute")
    # Returns UsageResult or nil
    def usage_for(product:, sku:, account_specific_lookup: true, include_budget: true)
      sku_breakdown = sku_breakdown_for(product: product, sku: sku)
      return unless sku_breakdown

      budgets, budget_limit = calculate_budgets_for(ids: sku_breakdown[:budget_ids], product: product) if include_budget
      total_consumed_quantity = sku_breakdown[:raw_quantities][:overage] + sku_breakdown[:entitlement_details][:quantity_consumed]
      account_consumed_quantity = enterprise_org_quantity_for(product: product, sku: sku) if account_specific_lookup
      account_consumed_cost = enterprise_org_cost_for(product: product, sku: sku) if account_specific_lookup

      UsageResult.new(
        name: sku_breakdown[:name],
        total_consumed_quantity: total_consumed_quantity,
        total_raw_consumed_quantity: sku_breakdown[:raw_quantities][:total],
        overage_consumed_quantity: sku_breakdown[:raw_quantities][:overage],
        entitlement_raw_quantity_consumed: sku_breakdown[:raw_quantities][:entitlement],
        entitlement_quantity_consumed: sku_breakdown[:entitlement_details][:quantity_consumed],
        estimated_cost: sku_breakdown[:estimated_overage_charge][:subunits],
        unit_of_measure: sku_breakdown.dig(:unit_of_measure, :name),
        entitlement: entitlements_for(id: sku_breakdown[:entitlement_details][:id]),
        budget_limit: budget_limit,
        budgets: budgets,
        unit_price: sku_breakdown[:unit_price],
        sku_multiplier: sku_breakdown[:entitlement_details][:multiplier],
        account_consumed_quantity: account_consumed_quantity,
        account_consumed_cost: account_consumed_cost
      )
    end

    # Public: The total estimated cost for skus
    #
    # args
    #   :usages - Array of UsageResult objects
    # Returns Integer or nil
    def total_paid_usage_for(usages:, account_specific_lookup: false)
      if account_specific_lookup && @is_enterprise_org
        usages.map { |usage| usage.account_consumed_cost }&.sum(0)
      else
        usages.map { |usage| usage.estimated_cost }&.sum(0)
      end
    end

    # Public: The total usage time for all given skus
    #
    # args
    #  :usages - Array of UsageResult objects
    # Returns Integer or nil
    def total_usage_time_for(usages:)
      usages.map { |usage| usage.total_consumed_quantity }&.sum
    end

    # Public: The total quantity for skus
    #
    # args
    #   :usages - Array of UsageResult objects
    # Returns Integer or nil
    def total_paid_usage_quantity_for(usages:)
      usages.map { |usage| usage.overage_consumed_quantity }&.sum(0)
    end

    # Public: Does billable_owner have a payment issue that restricts paid overages?
    #
    # Returns Boolean
    memoize def paid_overages_restricted_by_owner_payment_issue?
      return false if billable_owner.is_a?(Business)

      billable_owner.billing_attempts >= 2
    end

    # Public: Do any of the given budgets have unlimited_spending_limits?
    #
    # args
    #   :budgets - Array of Billing::Budget objects
    # Returns Boolean
    def unlimited_spending_limit_for?(budgets:)
      budgets.all? { |budget| budget.unlimited_spending_limit? }
    end

    # Public: Are any of the given budgets set up with spending limits?
    #
    # args
    #   :budgets - Array of Billing::Budget objects
    # Returns Boolean
    def has_spending_limit_set?(budgets:)
      return false unless budgets.present?
      unlimited_spending_limit_for?(budgets: budgets) || budget_limit(budgets: budgets) > 0
    end

    # Public: Did the billable owner have entitlements granted and used them all?
    #
    # args
    #   :entitlement - EntitlementResult object
    # Returns Boolean
    def exhausted_entitlement?(entitlement)
      return false unless entitlement
      entitlement.allocated_quantity > 0 && entitlement.remaining_quantity == 0
    end

    # Public: The total budget limit for given budgets.
    #
    # args
    #   :budgets - Array of Billing::Budget objects
    # Returns Integer
    def budget_limit(budgets:)
      return 0 if budgets.empty?
      budgets.min_by(&:usage_limit).usage_limit
    end

    # Did the meuse request end in an error
    def request_error?
      request_error
    end

    # Public: Returns an array of UsageResult objects for all SKUs for a given product
    #
    # args
    #   :product - String name product ("actions", "codespaces")
    # Returns Array
    def usage_results_for(product:, account_specific_lookup: true)
      usage_results = skus_for_product(product: product).map do |sku_breakdown|
        usage_for(product: product, sku: sku_breakdown[:name], account_specific_lookup:)
      end

      usage_results
    end

    # Public: Returns an array of usages across products from billing platform
    sig { returns(T::Hash[Symbol, T.untyped]) }
    def billing_platform_usage_results
      billing_platform_client = Billing::Platform::Api::Client.new
      billing_cycle_start_date = @account.current_metered_billing_cycle_starts_at

      billing_platform_client.get_net_usage_line_items(
        usage_entity_id: @account.customer.id.to_s,
        billing_period: BillingPlatform::Base::BillingPeriod::Monthly,
        year: billing_cycle_start_date.year,
        month: billing_cycle_start_date.month,
        day: nil,
        hour: nil,
      )
    end

    # Public: Returns the total metered usage in cents using usage from billing platform
    sig { returns(Integer) }
    def billing_platform_usage_results_in_cents
      total_usage = billing_platform_usage_results[:netUsageItems].select { |item| product_names.include? item[:product] }.sum { |u| u[:netAmount] }
      Billing::Money.parse(total_usage).cents
    end

    # Public: Returns the total metered usage in cents for the account
    sig { returns(Integer) }
    def total_usage_in_cents
      if account.customer&.billed_via_billing_platform?
        billing_platform_usage_results_in_cents
      else
        metered_products_usages = product_names.map do |metered_product|
          usage_results_for(product: metered_product)
        end
        total_paid_usage_for(usages: metered_products_usages.flatten(1))
      end
    end

    # Public: How much usage has been spent toward the given budget?
    # args
    #   :budget - Billing::Budget object
    # Returns Integer
    def total_spent_towards_budget(budget)
      return 0 if budget.codespaces? && !budget.persisted?
      budget_id = budget.id || 0
      @total_spend_for_budget ||= {}
      budget_detail = usage_breakdown[:budgets]&.find { |budget_detail| budget_detail[:id] == budget_id }
      return 0 unless budget_detail
      @total_spend_for_budget[budget_id] ||= budget_detail[:total_spent][:subunits]
    end

    # Public: The percentage of the total_spent towards a budget compared to the limit
    # args
    #   :budget - Billing::Budget object
    # Returns Integer
    sig { params(budget: Billing::Budget).returns(Integer) }
    def budget_percentage_used(budget)
      total_spent = total_spent_towards_budget(budget)
      return 0 if total_spent.zero?

      percent = (total_spent / budget.usage_limit.to_f).round(2)
      return 100 if percent == Float::INFINITY
      [(percent * 100).to_i, 100].min
    end

    private

    # Private: Billing::Budget objects from ids
    #
    # args
    #   :ids - Array of ids for Billing::Budget
    #   :product - String name of product to fall back to default budgets if ids can't be found
    # Returns Array of Billing::Budget objects
    def budgets_for(ids:, product:)
      budgets = billable_owner.budgets.select { |budget| ids.include?(budget.id) }

      if budgets.empty?
        budgets << account_product_budget(account: billable_owner, product: product)
      end

      if account != billable_owner && billable_owner.feature_enabled?(:ghe_spending_limits)
        org_level_budets = account.budgets.select { |budget| ids.include?(budget.id) }

        budgets.concat(org_level_budets)
      end

      budgets.compact
    end

    def calculate_budgets_for(ids:, product:)
      budgets = budgets_for(ids: ids, product: product)
      budget_limit = budget_limit(budgets: budgets)
      [budgets, budget_limit]
    end

    def account_product_budget(account:, product:)
      @account_product_budgets ||= {}

      @account_product_budgets[account] ||= {}
      @account_product_budgets[account][product] ||= if product == "codespaces"
        # TODO: Remove this once we have a way to get the budgets without checking specific product names
        # +--------------------+--------------+
        # |    Product name    | Budget group |
        # +--------------------+--------------+
        # | actions            | shared       |
        # | packages           | shared       |
        # | shared_storage     | shared       |
        # | codespaces_compute | codespaces   |
        # | codespaces_storage | codespaces   |
        # +--------------------+--------------+
        account.budget_for(group: product)
      else
        account.budget_for(product: product)
      end
    end

    # Private: Returns hash from response for a sku
    #
    # args
    #   :sku - String name sku
    # Returns Hash or nil
    def sku_breakdown_for(product:, sku:)
      skus_for_product(product: product).find { |sku_breakdown| sku_breakdown[:name] == sku }
    end

    # Private: Returns hash from response for skus under a product
    #
    # args
    #   :product - String name product ("actions", "codespaces")
    # Returns Array
    def skus_for_product(product:)
      product_breakdown = product_for(product: product)
      return [] unless product_breakdown

      product_breakdown[:sku_breakdowns]
    end

    # Private: Returns hash from response for a product
    #
    # args
    #   :product - String name product ("actions", "codespaces")
    # Returns Hash
    def product_for(product:)
      usage_breakdown[:product_breakdowns]&.find { |product_breakdown| product_breakdown[:name] == product }
    end

    # Private: Does the billable_owner have spending/budget limit remaining to use?
    #
    # args
    #   :usage - UsageResult object
    # Returns Boolean
    def has_budget_remaining?(usage:, additional_cost_in_subunits: 0)
      return true if unlimited_spending_limit_for?(budgets: usage.budgets)

      additional_cost_in_subunits = additional_cost_in_subunits.to_f
      if additional_cost_in_subunits.nan? || additional_cost_in_subunits < 0
        additional_cost_in_subunits = 0.0
      end

      usage.budgets.all? do |budget|
        budget_remaining = budget_limit(budgets: [budget]) - total_spent_towards_budget(budget)
        budget_remaining.positive? && (budget_remaining - additional_cost_in_subunits) >= 0
      end
    end

    def select_enterprise_org_usage_for(product:, sku:)
      return nil unless @is_enterprise_org
      return nil unless enterprise_org_usage_breakdown.key?(:product_usage)
      enterprise_org_usage_breakdown[:product_usage].select do |product_usage|
        product_usage[:product_sku][:name] == sku and product_usage[:product][:name] == product
      end
    end

    def enterprise_org_quantity_for(product:, sku:)
      usages = select_enterprise_org_usage_for(product: product, sku: sku)
      return nil unless usages
      usages&.sum { |product_usage| product_usage[:usage][:effective_quantity] }.round(2)
    end

    def enterprise_org_cost_for(product:, sku:)
      usages = select_enterprise_org_usage_for(product: product, sku: sku)
      return nil unless usages
      usages&.map { |product_usage| product_usage[:usage][:estimated_cost][:subunits] }&.sum(0)
    end

    memoize def enterprise_org_usage_breakdown
      request_enterprise_org_usage_breakdown
    end

    # Private: Request the list_product_usage endpoint
    # Returns Hash
    def request_enterprise_org_usage_breakdown
      response = client.list_product_usage(billable_owner.current_metered_billing_cycle_starts_at, product_names: product_names)

      if response.is_a?(Billing::Api::ClientWrapper::BillingClientError)
        @request_error = true
        return {}
      end
      response
    end


    # Private: Memoize the response from meuse
    # Returns Hash
    memoize def usage_breakdown
      request_usage_breakdown
    end

    # Private: Request the get_usage_breakdown endpoint
    # Returns Hash
    def request_usage_breakdown
      response = client.get_usage_breakdown(product_names: product_names)

      if response.is_a?(Billing::Api::ClientWrapper::BillingClientError)
        @request_error = true
        return {}
      end

      response
    end
  end
end
