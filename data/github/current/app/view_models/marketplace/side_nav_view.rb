# typed: true
# frozen_string_literal: true

class Marketplace::SideNavView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  include UrlHelpers

  attr_reader :viewing_pending_orders, :viewing_pending_installations, :selected_category
  alias_method :viewing_pending_orders?, :viewing_pending_orders
  alias_method :viewing_pending_installations?, :viewing_pending_installations
  delegate :category_slug, :tool_type, :verification_state, :copilot_app, to: :search_options, prefix: :selected
  alias_method :selected_copilot_app?, :selected_copilot_app

  def initialize(search_options: Marketplace::SearchOptions.new, use_search_paths: false, viewing_pending_orders: false, viewing_pending_installations: false, current_user: nil, user_session: nil)
    super
    @search_options = search_options
    @use_search_paths = use_search_paths
    @viewing_pending_orders = viewing_pending_orders
    @viewing_pending_installations = viewing_pending_installations
    @categories = marketplace_categories
    @viewer = current_user if logged_in?
    @selected_category = selected_marketplace_category
  end

  def tool_type_options
    Marketplace::SearchOptions::LISTING_TYPES
  end

  def verification_state_options
    Marketplace::SearchOptions::VERIFICATION_STATES_APP_MIGRATION
  end

  def navigation_categories
    navigation_categories = []
    categories.each do |category_id, category|
      navigation_categories << Category.new(categories, category_id, category[:slug], category[:name]) unless category[:parent_id]
    end
    navigation_categories
  end

  def filter_categories
    filter_categories_hash = marketplace_filter_categories
    filter_categories = []
    filter_categories_hash.each do |category_id, category|
      filter_categories << Category.new(filter_categories_hash, category_id, category[:slug], category[:name])
    end
    filter_categories
  end

  def selected_marketplace_category
    if selected_category_slug.present?
      return Marketplace::Category.find_by(slug: selected_category_slug)
    end
    nil
  end

  def selected_category_is_a_filter?
    selected_category_slug.present? &&
      filter_categories.any? { |category| category.has_slug?(selected_category_slug) }
  end

  def prefilled_search_path(overrides = {})
    params = search_options.as_params(overrides)
    marketplace_search_path(params)
  end

  def category_or_prefilled_search_path(slug:)
    if use_search_paths?
      prefilled_search_path(category: slug)
    else
      marketplace_category_path(slug)
    end
  end

  def show_user_items?
    viewer.present?
  end

  def viewer_has_pending_orders?
    viewer_order_previews_count > 0
  end

  def viewer_has_pending_installations?
    viewer_pending_installations_count > 0
  end

  def viewer_has_purchases?
    viewer_purchases_count > 0
  end

  def viewer_has_listings?
    viewer_listings_count > 0
  end

  class Category
    def initialize(categories, category_id, slug, name, subcategory: false)
      @slug = slug
      @name = name
      @sub_categories = []
      initialize_sub_categories(categories, category_id) unless subcategory
    end

    def initialize_sub_categories(categories, category_id)
      sub_categories_hash = categories.select { |_category_key, category_hash| category_hash[:parent_id] == category_id }
      if sub_categories_hash.present?
        sub_categories_hash.each do |sub_category_id, sub_category|
          @sub_categories << Category.new(categories, sub_category_id, sub_category[:slug], sub_category[:name], subcategory: true)
        end
      end
    end

    def has_slug?(other_slug)
      slug == other_slug
    end

    def has_slug_or_children_has_slug?(other_slug)
      has_slug?(other_slug) ||
        sub_categories&.any? { |subcategory| subcategory.has_slug?(other_slug) }
    end

    attr_reader :slug, :name, :sub_categories
  end

  private

  attr_reader :search_options, :use_search_paths, :viewer, :categories
  alias_method :use_search_paths?, :use_search_paths

  def viewer_order_previews_count
    return 0 unless viewer
    viewer.marketplace_order_previews.with_valid_listing_data.count
  end

  def viewer_purchases_count
    return 0 unless viewer
    Billing::SubscriptionItem.with_marketplace_listing_plans_type
      .joins(:plan_subscription)
      .where(plan_subscriptions: { user_id: viewer.user_or_org_account_ids })
      .active.count
  end

  def viewer_listings_count
    return 0 unless viewer
    Marketplace::Listing.editable_by(viewer).count
  end

  def viewer_pending_installations_count
    return 0 unless viewer
    viewer.pending_marketplace_installations.count
  end

  def marketplace_categories
    categories_hash(marketplace_category_array)
  end

  def marketplace_filter_categories
    categories_hash(marketplace_category_array(filter: true))
  end

  def categories_hash(categories_array)
    categories_hash = {}
    categories_array.each { |category| categories_hash[category[0]] = ({ slug: category[1], name: category[2], parent_id: category[3] }) }
    categories_hash
  end

  def marketplace_category_array(filter: false)
    categories = ::Marketplace::Category.order(:name).not_sponsors_only

    if filter
      categories = categories.where(slug: %w[free paid free-trials github-enterprise github-partners])
    else
      categories = categories.navigation_visible.with_listings
    end

    categories.pluck(:id, :slug, :name, :parent_category_id)
  end
end
