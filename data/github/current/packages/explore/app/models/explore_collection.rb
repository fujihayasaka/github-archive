# typed: false
# frozen_string_literal: true

class ExploreCollection < ApplicationRecord::Ballast
  MAX_DISPLAY_NAME_LENGTH = 100
  MAX_SLUG_LENGTH = 40
  NUMBER_OF_FEATURED_COLLECTIONS = 3
  SLUG_REGEX = /\A[a-z0-9][a-z0-9-]*\Z/
  URL_REGEX = %r{\Ahttps?://}.freeze
  IMAGE_EXTENSION_REGEX = %r{.*(jpg|jpeg|png|gif)\Z}.freeze

  cattr_accessor :per_page, default: 20


  include GitHub::Relay::GlobalIdentification

  attribute :display_name, StringFromBinary.new
  attribute :description, StringFromBinary.new
  attribute :slug, StringFromBinary.new
  attribute :created_by, StringFromBinary.new

  self.table_name = :collections
  before_validation :normalize_slug

  has_many :items, class_name: "CollectionItem",
    dependent: :destroy, foreign_key: "collection_id", inverse_of: :collection

  validates :display_name, presence: true, length: { maximum: MAX_DISPLAY_NAME_LENGTH }
  validates :slug, presence: true, length: { maximum: MAX_SLUG_LENGTH },
    format: {
      with: SLUG_REGEX,
      message: "can only include letters, numbers, and hyphens, e.g., front-end-javascript-frameworks",
    }
  validates :slug, uniqueness: { case_sensitive: false }, if: -> { errors[:slug].blank? }

  validates :attribution_url,
    format: { with: URL_REGEX, message: "must be a valid URL", allow_nil: true }

  validates :image_url,
    format: { with: URL_REGEX, message: "must be a valid URL", allow_nil: true }

  validates :image_url, format: {
    with: IMAGE_EXTENSION_REGEX,
    message: "must contain a supported image extension",
    allow_nil: true,
  }

  scope :featured, -> { where(featured: true) }
  scope :non_featured, -> { where(featured: false) }
  scope :with_name_like, ->(query) {
    sanitized_query = "#{ActiveRecord::Base.sanitize_sql_like(query)}%"
    where("collections.display_name LIKE ?", sanitized_query)
  }


  def self.valid_slug?(slug)
    slug.present? && slug.length <= MAX_SLUG_LENGTH && slug =~ SLUG_REGEX
  end

  def self.featured_and_shuffled(limit: NUMBER_OF_FEATURED_COLLECTIONS)
    featured
      .order("RAND()")
      .limit(limit)
  end

  def to_param
    slug
  end

  def to_s
    slug
  end

  # Public: Render the collection's description as a truncated, simplified
  # HTML document.
  def short_description_html(limit: 200)
    formatted = GitHub::Goomba::SimpleDescriptionPipeline.to_html(description)
    HTMLTruncator.new(formatted, limit).to_html(wrap: false)
  end

  # Public: Asynchronous implementation of #short_description_html.
  def async_short_description_html(limit: 200)
    GitHub::Goomba::SimpleDescriptionPipeline.async_to_html(description).then do |formatted|
      HTMLTruncator.new(formatted, limit).to_html(wrap: false)
    end
  end

  private

  def normalize_slug
    return unless slug
    self.slug = self.slug.downcase.gsub("_", "-")
  end
end
