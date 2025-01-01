# typed: true
# frozen_string_literal: true

class IntegrationListing < ApplicationRecord::Domain::Integrations
  include GitHub::Validations
  include GitHub::UserContent

  extend GitHub::Encoding
  force_utf8_encoding :body

  # The org or user that owns the integration via the OauthApplication
  delegate :owner, to: :integration

  # Polymorphic association of the item being listed. This allows us to use OAuthApplication,
  # Integrations, and the future of GitHubServices.
  # column :integration_type
  # column :integration_id
  belongs_to :integration, polymorphic: true
  validates :integration, presence: true
  before_validation :ensure_integration_is_visible, on: :create

  # The short blurb shown on the Integrations listings page.
  # column :blurb
  validates :blurb, presence: true, unicode3: true

  # The long form marketing description for the Integration.
  # column :body
  validates :body, presence: true

  # Track the state of this listing if it should be public or delisted.
  # column :state
  #
  #  :draft       - Used to troubleshoot/verify listing details before going live to the public.
  #  :published   - Used when listing is visible to the public.
  #  :delisted    - Used to denote that a GitHub employee removed a previously visible listing
  #                 from the directory.
  enum :state, { draft: 0, published: 1, delisted: 2 }

  # Public: String name of this integration listing.
  # column :name
  validates :name, presence: true, unicode3: true
  before_validation :set_name

  # The URI friendly feature slug
  # column :slug
  validates :slug, presence: true, unicode3: true
  validates :slug, uniqueness: { case_sensitive: false }, if: -> { T.bind(self, IntegrationListing).errors[:slug].blank? }
  validate :denied_slugs
  before_validation :generate_slug, on: :create

  scope :draft_and_published, -> { where(state: states.values_at(:draft, :published)) }

  # The URL at the third-party that will redirect to the correct GitHub authorization endpoint.
  # The URL at the third-party that will explain more about the service being offered.
  # column :installation_url
  # column :learn_more_url
  validate :has_one_redirection_url
  # TODO Validate that the URL is a valid URL

  # A Privacy Policy is a required for security and legal.
  validates :privacy_policy_url, presence: true

  has_many :integration_listing_features, dependent: :destroy
  has_many :features, through: :integration_listing_features, source: :integration_feature

  # Languages that this integration supports (if any)
  has_many :integration_listing_language_names, dependent: :destroy
  has_many :languages,
           through: :integration_listing_language_names,
           source: :language_name,
           disable_joins: true

  # Public: Select IntegrationListings in the given feature.
  #
  # feature_slug - the slug of the IntegrationFeature to select or nil.
  #
  # Returns an ActiveRecord::Relation.
  def self.with_feature(feature_slug)
    if feature_slug.present?
      joins(:features).where(integration_features: { slug: feature_slug })
    else
      scoped
    end
  end

  # Public: Select IntegrationListings that match the query by title or body.
  #
  # feature_name - the query to search for or nil.
  #
  # Returns an ActiveRecord::Relation.
  def self.matches_name_or_description(query)
    if query.present?
      where("`name` LIKE ? OR `body` LIKE ?",
            "%#{query}%",
            "%#{query}%")
    else
      scoped
    end
  end

  # Public: Return the client ID of the listing's associated OAuth application.
  #
  # Returns a String.
  def client_id
    integration.key
  end

  # Internal: Generate a URI friendly slug that will be used for navigation. We want this slug to
  # SEO worthy and human friendly so if we can't generate a unique friendly slug, we'll just error
  # back to the GitHub staff creating the feature.
  def generate_slug
    regexp = /[^\p{Word}]+/
    if self.slug.blank?
      self.slug = T.must(name).downcase.gsub(regexp, "-").chomp("-")
    end
  end

  # Internal: Specify the pipeline to override settings in UserContent.
  def body_pipeline
    GitHub::Goomba::IntegrationListingPipeline
  end

  # Public
  def to_param
    slug
  end

  def integrations_two_listing?
    integration.is_a?(Integration)
  end

  # Internal: Ensure the integration we are listing
  # is available to everyone.
  def ensure_integration_is_visible
    return unless integration.present?
    return unless integration.is_a?(Integration)

    integration.make_public! if integration.private_visibility?
  end

  # Internal: Set the name of this integration on create
  def set_name
    return if name.present?
    return unless integration.present?

    self.name = integration.name
  end

  def slug_disallowed?
    ["categories"].include? slug
  end

  private

  def has_one_redirection_url # rubocop:disable Naming/PredicateName
    if installation_url.blank? && learn_more_url.blank?
      errors.add(:base, "An integration listing must have either an installation URL or a learn more URL")
    end
  end

  # Private: A validation to ensure that the slug is permitted
  def denied_slugs
    return if slug.blank?
    if slug_disallowed?
      errors.add(:slug, "is a reserved word")
      false
    end
  end
end
