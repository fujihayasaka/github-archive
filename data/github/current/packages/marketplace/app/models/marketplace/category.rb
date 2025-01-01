# typed: true
# frozen_string_literal: true

class Marketplace::Category < ApplicationRecord::Domain::Integrations
  self.table_name = "marketplace_categories"

  include GitHub::Relay::GlobalIdentification
  include GitHub::Validations
  extend GitHub::Encoding
  force_utf8_encoding :description, :how_it_works

  SUBCATEGORIES_LIMIT = 3
  CATEGORIES_WITH_RECOMMENDATIONS = {
    "continuous-integration" => %w[project-management deployment],
    "project-management"     => %w[continuous-integration code-quality],
    "code-quality"           => %w[continuous-integration security],
  }
  SPONSORS_ONLY_CATEGORIES = %w[Community Sponsorable].freeze

  belongs_to :parent_category,
    class_name: "Marketplace::Category",
    optional:   true

  # rubocop:todo Rails/InverseOf
  has_many :sub_categories,
    class_name:  "Marketplace::Category",
    foreign_key: "parent_category_id"
  # rubocop:enable Rails/InverseOf

  has_and_belongs_to_many :listings,
    class_name:              "Marketplace::Listing",
    foreign_key:             "marketplace_category_id",
    association_foreign_key: "marketplace_listing_id"

  # rubocop:todo Rails/InverseOf
  has_many :marketplace_categories_repository_actions, foreign_key: :marketplace_category_id
  # rubocop:enable Rails/InverseOf

  has_many :actions,
    class_name: "RepositoryAction",
    through: :marketplace_categories_repository_actions,
    source: :repository_action,
    foreign_key: :marketplace_category_id,
    disable_joins: true

  RESERVED_NAMES = %w(none).freeze

  before_validation :generate_slug
  before_validation :reset_featured_position, unless: :featured?

  DESCRIPTION_MAX_LENGTH = 160

  validates :name, :slug, :description, presence: true
  validates :name, :slug, unicode3: true
  validates :name, uniqueness: { case_sensitive: false }, if: -> { T.unsafe(self).errors[:name].blank? }
  validates :slug, uniqueness: { case_sensitive: false }, if: -> { T.unsafe(self).errors[:slug].blank? }
  validates :description, length: { in: 1..DESCRIPTION_MAX_LENGTH }
  validate :name_is_not_restricted
  validate :slug_not_reserved_by_listing
  validate :parent_category_is_not_self
  validate :single_level_of_subcategories
  validate :no_primary_listings, if: :acts_as_filter?

  validates :featured_position, uniqueness: true, allow_nil: true, if: :featured?
  validates :featured_position, presence: { message: "required to feature this category" }, if: :featured?

  # Return only categories that have associated listings. For display purposes,
  # a category is considered empty if there are no listings where it is primary
  # and less than 2 listings where it is secondary.
  scope :with_listings, -> {
    where("primary_listing_count > 0 OR secondary_listing_count > 1")
  }

  # Return categories that can be used as subcategories. When an optional
  # category is given, it is excluded from the list since a category cannot be a
  # subcategory of itself.
  scope :subcategory_candidates, -> (for_optional_slug: nil) {
    categories_without_subcategories = left_joins(:sub_categories)
      .group(:id)
      .having("COUNT(sub_categories_marketplace_categories.id) = 0")

    if for_optional_slug
      categories_without_subcategories.where.not(slug: for_optional_slug)
    else
      categories_without_subcategories
    end
  }

  # Returns categories where a matching `slug` is found as a `Category`
  # or parent `Category`
  scope :for_slug, -> (slug) {
    left_joins(:parent_category).where(slug: slug).or(
      left_joins(:parent_category).where(parent_categories_marketplace_categories: { slug: slug })
    )
  }

  scope :navigation_visible, -> { where(navigation_visible: true) }
  scope :top_level, -> { where(parent_category_id: nil) }
  scope :featured, -> { where(featured: true).order(:featured_position) }
  scope :not_sponsors_only, -> { where.not(slug: SPONSORS_ONLY_CATEGORIES) }

  TOPIC_SLUG_MAPPINGS = {
    "quality" => "code-quality",
    "ci" => "continuous-integration",
    "dependencies" => "dependency-management",
    "dependency-manager" => "dependency-management",
    "deploy-tool" => "deployment",
    "deployment-manager" => "deployment",
    "localisation" => "localization",
    "monitor" => "monitoring",
    "metrics" => "monitoring",
    "ticketing" => "support",
    "helpdesk" => "support",
    "testing-tools" => "testing",
  }.freeze

  def self.slug_for_topic(topic_name)
    TOPIC_SLUG_MAPPINGS[topic_name]
  end

  def to_s
    name
  end

  def async_filtered_subcategories(for_navigation:, limit: nil)
    if for_navigation
      Promise.resolve(sub_categories.navigation_visible.with_listings.limit(limit))
    else
      Promise.resolve(sub_categories.limit(limit))
    end
  end

  def platform_type_name
    "MarketplaceCategory"
  end

  private

  def generate_slug
    if slug.nil? || name_changed?
      self.slug = name.try(:parameterize)
    end
  end

  def name_is_not_restricted
    if RESERVED_NAMES.include?(name)
      errors.add(:name, "is reserved, please rename the category")
    end
  end

  def slug_not_reserved_by_listing
    if Marketplace::Listing.where(slug: slug).exists?
      errors.add(:slug, "is reserved by a Listing, please rename the category")
    end
  end

  def parent_category_is_not_self
    return unless parent_category_id && parent_category_id == self.id
    errors.add(:parent_category, "cannot be itself")
  end

  def single_level_of_subcategories
    return unless parent_category_id && sub_categories.any?
    errors.add(:parent_category, "cannot be set because this category has subcategories")
  end

  def no_primary_listings
    primary_listing = Marketplace::Listing
      .with_category(slug)
      .for_primary_category_only

    return unless primary_listing.exists?
    errors.add(:acts_as_filter, "cannot be a filter because it has primary listings")
  end

  def reset_featured_position
    self.featured_position = nil
  end
end
