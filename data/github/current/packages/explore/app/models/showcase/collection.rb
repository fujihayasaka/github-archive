# typed: false
# frozen_string_literal: true

require "geo_pattern"

class Showcase::Collection < ApplicationRecord::Domain::Showcases
  extend GitHub::SimplePagination

  include GitHub::UserContent

  self.table_name = "showcase_collections"
  belongs_to :owner, class_name: "User"
  has_many :items, class_name: "Showcase::Item", dependent: :destroy
  has_many :repositories,
    through: :items,
    source: :item,
    source_type: "Repository",
    disable_joins: true

  validates_presence_of :name
  validates_uniqueness_of :slug, case_sensitive: false

  before_validation :set_default_slug

  after_commit :synchronize_search_index
  after_destroy :synchronize_search_index

  scope :published, -> { where(published: true) }
  scope :featured, -> { where(featured: true) }
  scope :draft, -> { where(published: false) }

  TOPIC_MAPPINGS = {
    "-net-community-projects" => "dotnet",
    "ember-projects" => "ember",
    "open-source-operating-systems" => "operating-system",
    "serverless-architecture" => "serverless",
    "web-application-frameworks" => "framework",
    "security" => "security",
    "data-visualization" => "data-visualization",
    "emoji" => "emoji",
    "fonts" => "fonts",
    "package-managers" => "package-manager",
    "virtual-reality" => "virtual-reality",
    "3d-modeling" => "3d-modeling",
    "icon-fonts" => "icon-fonts",
    "nosql-databases" => "nosql",
    "swift" => "swift",
  }.freeze

  DELETED_SLUGS = %w[open-source-integrations writing extending-unreal-engine game-development-tools game-off-2016-entries hacking-finance mysql robotics-drones-and-the-internet-of-things unity-projects wtfork debug-politics fabric-mobile-developer-tools game-off-winners video-tools projects-with-great-wikis css-preprocessors universal-2nd-factor].freeze
  COLLECTION_SLUGS = %w[programming-languages text-editors github-browser-extensions hacking-minecraft projects-that-power-github made-in-africa web-accessibility software-development-tools devops-tools tools-for-open-source machine-learning github-pages-examples learn-to-code open-data policies open-journalism government open-source-organizations social-impact clean-code-linters productivity-tools software-defined-radio music front-end-javascript-frameworks design-essentials web-games game-engines javascript-game-engines].freeze

  # Internal: Generate a milestone slug from the title.
  #
  # Returns a string slug suitable for use in URLs and topics.
  def generate_slug
    regexp = /[^\p{Word}]+/
    name.downcase.gsub(regexp, "-").chomp("-")
  end

  # Internal: Generate a milestone slug from the title that is unique amongst
  # all other milestones for this repository.
  #
  # Returns a string slug suitable for use in URLs and topics.
  def generate_unique_slug
    base_slug = generate_slug
    slug = base_slug
    count = 0
    scope = self.class.all
    scope = scope.where("id != ?", id) unless id.nil?
    while scope.where(slug: slug).any?
      count += 1
      slug = "#{base_slug}-#{count}"
    end

    slug
  end

  def to_param
    self.slug
  end

  def to_s
    name
  end

  def synchronize_search_index(*args)
    if self.destroyed?
      RemoveFromSearchIndexJob.perform_later("showcase_collection", self.id)
    else
      Search.add_to_search_index("showcase_collection", self.id)
    end

    self
  end

  def geo_pattern
    GeoPattern.generate(self.name, { base_color: "#C44040" }).to_data_uri
  end

  # Get a unique array of the languages used in this showcase
  def languages
    return @languages if defined? @languages

    item_languages = repositories.includes(:primary_language).map(&:primary_language)

    @languages = item_languages.compact.uniq
  end

  protected

  # Set the default slug to a unique value. This is called before validation
  # when the cluster is created. If the slug generated from the name is not
  # unique, a numeric suffix is added and incremented until a unique slug is found.
  def set_default_slug
    return unless slug_update_allowed?
    self.slug = generate_unique_slug
  end

  def slug_update_allowed?
    name.present? && !(published? && !new_record?)
  end
end
