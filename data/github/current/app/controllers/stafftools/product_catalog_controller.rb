# typed: strict
# frozen_string_literal: true

class Stafftools::ProductCatalogController < StafftoolsController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Billing,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:index, :show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show],
    optional: true

  PER_PAGE = 30

  sig { void }
  def index
    type_filter = T.cast(params[:type_filter] || "all", String)
    metered_filter = T.cast(params[:metered_filter] || "all", String)
    page = params[:page]&.to_i || 1

    product_uuids = get_product_uuids(type_filter: type_filter, metered_filter: metered_filter).paginate(page: page, per_page: PER_PAGE)
    billing_platform_products = fetch_billing_platform_products if metered_filter == "metered"

    render "stafftools/product_catalog/index", locals: {
      product_uuids: product_uuids,
      type_filter: type_filter,
      metered_filter: metered_filter,
      type_filter_options: type_filter_options,
      metered_filter_options: metered_filter_options,
      billing_platform_products: billing_platform_products
    }
  end

  sig { void }
  def show
    product_uuid = Billing::ProductUUID.find(params[:id])
    billing_platform_product = fetch_billing_platform_product(product_uuid) if product_uuid.metered?

    render "stafftools/product_catalog/show", locals: {
      product_uuid: product_uuid,
      billing_platform_product: billing_platform_product,
    }
  end

  private

  sig { returns(T::Array[T::Hash[Symbol, String]]) }
  def type_filter_options
    [
      { label: "All", value: "all" },
      { label: "GitHub", value: "github" },
      { label: "Sponsors", value: "sponsors" },
      { label: "Marketplace", value: "marketplace" },
      { label: "Coupons", value: "coupons" }
    ]
  end

  sig { returns(T::Array[T::Hash[Symbol, String]]) }
  def metered_filter_options
    [
      { label: "All", value: "all" },
      { label: "Metered", value: "metered" },
      { label: "Non-Metered", value: "nonmetered" }
    ]
  end

  sig { params(type_filter: String, metered_filter: String).returns(ActiveRecord::Relation) }
  def get_product_uuids(type_filter:, metered_filter:)
    scope = Billing::ProductUUID.all

    # Apply type filter
    case type_filter
    when "github"
      scope = scope.github_products
    when "sponsors"
      scope = scope.sponsors
    when "marketplace"
      scope = scope.marketplace
    when "coupons"
      scope = scope.discounts
    end

    # Apply metered filter
    case metered_filter
    when "metered"
      scope = scope.metered
    when "nonmetered"
      # For non-metered, exclude metered products
      scope = scope.where(metered: false)
    end

    scope.order(:product_type, :product_key, :billing_cycle)
  end

  sig { returns(T::Hash[T.untyped, T.untyped]) }
  def fetch_billing_platform_products
    # Gracefully handle Billing Platform API failures to avoid circular dependencies
    client = Billing::Platform::Api::Client.new(timeout: 5)
    response = client.get_all_products

    return {} if response.is_a?(Billing::Platform::Api::Error)

    # Convert to hash keyed by SKU for easy lookup
    (response[:products] || []).index_by { |p| p[:sku] }
  rescue StandardError => e
    GitHub.logger.warn("Failed to fetch Billing Platform products: #{e.message}")
    {}
  end

  sig { params(product_uuid: Billing::ProductUUID).returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
  def fetch_billing_platform_product(product_uuid)
    return nil unless product_uuid.metered?

    client = Billing::Platform::Api::Client.new(timeout: 5)
    # Use product_key as SKU
    response = client.get_product(product_uuid.product_key)

    return nil if response.is_a?(Billing::Platform::Api::Error)

    response[:product]
  rescue StandardError => e
    GitHub.logger.warn("Failed to fetch Billing Platform product for #{product_uuid.id}: #{e.message}")
    nil
  end
end
