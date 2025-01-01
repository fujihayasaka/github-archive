# typed: true
# frozen_string_literal: true

# A metered billing product configured by config/metered_products.yml
class Billing::MeteredProduct
  UnknownProductError = Class.new(StandardError)
  UnknownProductSkuError = Class.new(StandardError)

  attr_reader :name, :enabled, :budget_group, :prepaid_budget_group, :skus
  alias_method :enabled?, :enabled

  # Public: List all known metered products
  # Returns Array
  def self.all
    indexed_metered_products.values
  end

  # Public: Determine if a metered product with a given name exists
  #
  # name - The name of the metered product to check
  #
  # Returns Boolean
  def self.exists?(name)
    indexed_metered_products.key?(name)
  end

  # Public: Look up a specific metered product by name
  #
  # name - The name of the metered product to look up
  #
  # Returns MeteredProduct
  # Raises UnknownProductError if the metered product cannot be found
  def self.find(name)
    indexed_metered_products.fetch(name.to_s) do
      raise UnknownProductError, "Unknown metered product #{name}"
    end
  end

  def self.effective_rate_plan_for(product:, sku:, account: nil, date: nil)
    sku = :linux if sku.to_s.downcase == "ubuntu"
    product_sku = find(product).skus.fetch(sku) do
      raise UnknownProductSkuError, "Unknown SKU #{sku} for the metered product #{product}"
    end

    product_sku.rate_plan_for(account: account, as_of: date) || product_sku.rate_plan_for(account: account)
  end

  # Generate UUID hash for given ID string
  #
  # The hydro schema meuse.v0.MeteredUsage is using field usage_uuid as an idempotency key.
  # The goal is to enable the product code to safely retry/replay usage messages without the risk of overcharging
  # customers. The value if expected to be formatted as UUID.
  #
  # Each product has to identify a suitable value to be used as an idempotency key. For example, for GitHub
  # Actions this would be the job ID. For GitHub Packages this would be the download ID.
  #
  # Use this method if your product's idempotency key is not in UUID format, i.e. when it is numeric.
  # Prefix the provided ID with a fixed string unique to your product to avoid collisions with numeric IDs
  # of other products.
  #
  # You don't have to use this method if your idempotency key is in UUID format already.
  def self.usage_uuid(unique_id)
    # uuid_v3 uses MD5 hash. Given this is only used as an idempotency key,
    # potential collisions have no security impact. Change of the digest algorithm is not trial because
    # it would break the idempotency.
    Digest::UUID.uuid_v3(Digest::UUID::OID_NAMESPACE, unique_id) # rubocop:disable GitHub/InsecureHashAlgorithm
  end

  private

  # Internal: Initializes a new MeteredProduct
  #
  # This method is intended to be called with data from config/metered_products.yml and should not be
  # used for any other purposes outside of this class.
  #
  # name                 - The name of the metered product
  # catalog_service      - The Catalog Service which creates metered usage
  # enabled              - Whether or not the metered product is available in production
  # budget_group         - Which Billing::Budget group ("product") applies to this product for post-paid customers
  # prepaid_budget_group - Which Billing::Budget group ("product") applies to this product for pre-paid customers
  # skus                 - An array of SKUs (see the Sku class below)
  def initialize(name:, enabled:, budget_group: nil, prepaid_budget_group: nil, skus: [])
    @name = name
    @enabled = !!enabled
    @budget_group = budget_group
    @prepaid_budget_group = prepaid_budget_group
    @skus = skus.map { |data| Sku.new(**data.symbolize_keys) }.index_by(&:name).with_indifferent_access
  end

  # Internal: All metered products indexed by name
  # Returns Hash
  def self.indexed_metered_products
    return @indexed_metered_products if defined?(@indexed_metered_products)

    config = YAML.safe_load_file(Rails.root.join("config", "metered_products.yml"), permitted_classes: [Date], aliases: true)
    @indexed_metered_products = config.map { |data| new(**data.symbolize_keys) }.index_by(&:name)
  end
  private_class_method :indexed_metered_products

  # An individual SKU of a given metered product
  # SKUs allow differentiation within a given metered product
  class Sku
    attr_reader :name, :unit_of_measure, :rate_plans

    # Internal: Initializes a new Sku
    #
    # name                      - The name of the SKU
    # unit_of_measure           - The logical unit of measure in which usage is stored in the database
    # rate_plans                - An Array of rate plans (see the RatePlan class below)
    def initialize(name:, unit_of_measure:, rate_plans: [])
      @name = name
      @unit_of_measure = unit_of_measure
      @rate_plans = rate_plans.map { |data| RatePlan.new(**data.symbolize_keys) }
    end

    # Public: Look up the current rate plan for a given Github plan
    #
    # plan - The GitHub plan criterion
    # account - The account the rate plan is for, which enables account specific feature flags.
    #
    # Returns RatePlan
    def rate_plan_for(plan: nil, account: nil, as_of: nil)
      rate_plans.select do |rate_plan|
        rate_plan.effective?(account: account, as_of: as_of) &&
        (plan.nil? || rate_plan.github_plans.include?(plan.name))
      end.sort_by(&:effective_on).last
    end
  end

  # An individual rate plan defining how we bill and charge for a particular product SKU
  class RatePlan
    attr_reader :effective_on, :github_plans, :overages, :multiplier,
      :feature_flag, :override_effective_on_feature_flag

    # Internal: Initializes a new RatePlan
    #
    # effective_on - The date that the rate plan becomes effective (at midnight Pacific time)
    # github_plans - An Array of GitHub plan names to which the rate plan applies
    # overages     - A Hash of pricing details for overages (see the RatePlanOverage class below)
    # multiplier   - A multiplier to apply to usage in pricing and included usage calculations
    # feature_flag - A String tied to a feature_flag that can be used to enable/disable a rate plan.
    # override_effective_on_feature_flag - A String tied to a feature_flag that can be used to override
    #                                      the effective_on column to enable a rate plan
    def initialize(effective_on:, github_plans:, overages:, multiplier: 1, azure: {},
                   feature_flag: nil, override_effective_on_feature_flag: nil)
      @effective_on = effective_on
      @github_plans = github_plans
      @overages = RatePlanOverage.new(**overages.symbolize_keys)
      @multiplier = multiplier
      @feature_flag = feature_flag
      @override_effective_on_feature_flag = override_effective_on_feature_flag
    end

    # Public: Whether or not this rate plan is effective
    #
    # as_of - The date criterion (default today)
    # account - The account a rate plan can be effective for. This allows account specific feature flag
    # toggling.
    #
    # Returns Boolean
    def effective?(as_of: GitHub::Billing.today, account: nil)
      as_of ||= GitHub::Billing.today
      effective_on <= as_of
    end

    # Public: The per-unit price for overages
    # Returns BigDecimal
    def overage_price
      overages.price
    end
  end

  # Structured overage pricing
  class RatePlanOverage
    attr_reader :price, :unit_of_measure

    # Internal: Initializes a new RatePlanOverage
    #
    # price           - The price for each unit of overage usage
    # unit_of_measure - The unit of measure in which the price is given (see the UnitOfMeasure class below)
    def initialize(price:, unit_of_measure:)
      @price = BigDecimal(price)
      @unit_of_measure = UnitOfMeasure.new(**unit_of_measure.symbolize_keys)
    end
  end

  # Structured unit of measure
  class UnitOfMeasure
    attr_reader :name, :scale

    # Internal: Initializes a new UnitOfMeasure
    #
    # name  - The name of the unit of measure
    # scale - The scale relative to a base unit of measure
    def initialize(name:, scale: 1)
      @name = name
      @scale = scale
    end
  end
end
