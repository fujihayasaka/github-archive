# typed: true
# frozen_string_literal: true

class IntegrationFeature < ApplicationRecord::Domain::Integrations
  include GitHub::UserContent
  include GitHub::Validations

  # The feature's name (ex, Continuous Integration)
  # column :name
  validates :name, presence: true, unicode3: true
  validates :name, uniqueness: { case_sensitive: false }, if: -> { T.bind(self, IntegrationFeature).errors[:name].blank? }

  # The description shown below the feature
  # column :body
  validates :body, presence: true

  # The URI friendly feature slug
  # column :slug
  validates :slug, presence: true, uniqueness: { case_sensitive: false }, unicode3: true
  before_validation :generate_slug, if: :name_changed?

  has_many :integration_listing_features
  has_many :listings, through: :integration_listing_features, source: :integration_listing

  # Track the state of this feature if it should be visible and or filterable
  # column :state
  #
  #  :draft       - Default state. Feature is being built but shouldn't be visible or filterable.
  #  :visible     - Feature will display on IntegrationListing pages.
  #  :filterable  - Feature will display on IntegrationListing pages and will also appear within
  #                 the filtering bar.
  #  :hidden      - Feature is hidden for changes or temporary problems.
  enum :state, { draft: 0, visible: 1, filterable: 2, hidden: 3 }

  scope :at_least_visible, -> { where(state: states.values_at(:visible, :filterable)) }
  scope :not_visible, -> { where(state: [:draft, :hidden]) }

  # Internal: Generate a URI friendly slug that will be used for navigation. We want this slug to
  # SEO worthy and human friendly so if we can't generate a unique friendly slug, we'll just error
  # back to the GitHub staff creating the feature.
  def generate_slug
    regexp = /[^\p{Word}]+/
    self.slug = name.downcase.gsub(regexp, "-").chomp("-")
  end

  # Internal: Specify the pipeline to override settings in UserContent.
  def body_pipeline
    GitHub::Goomba::IntegrationListingPipeline
  end

  def self.ordered
    order(:name)
  end

  # Returns true if the feature appears on integration listing pages or appears within the
  # filtering bar.
  def visible?
    super || filterable?
  end

  def self.viewer_can_read?(viewer)
    return false unless viewer
    viewer.github_developer? || viewer.site_admin?
  end
end
