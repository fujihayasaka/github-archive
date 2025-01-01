# typed: true
# frozen_string_literal: true

class GitHubModels::Publisher < ApplicationRecord::Domain::GitHubModels
  self.table_name = "models_publishers"

  before_validation :set_logo_url

  validates :name, presence: true, uniqueness: true, length: { maximum: 50 }
  validates_presence_of :logo_url

  has_many :organization_access_rules, class_name: "GitHubModels::OrganizationAccessRule",
    foreign_key: "models_publisher_id", inverse_of: :publisher

  has_many :catalog_items, class_name: "GitHubModels::CatalogItem", inverse_of: :publisher

  scope :alphabetical, -> { order(name: :asc) }

  # Public: Get a hash mapping publisher IDs to a count of how many models are associated with the publisher.
  sig { params(catalog_items: T::Array[GitHubModels::CatalogItem]).returns(T::Hash[Integer, Integer]) }
  def self.model_counts_by_id(catalog_items)
    catalog_items.each_with_object(Hash.new(0)) do |catalog_item, hash|
      hash[catalog_item.github_models_publisher_id] += 1
    end
  end

  sig { params(total_models: T.nilable(Integer)).returns(GitHubModels::Types::Publisher) }
  def to_h(total_models: nil)
    {
      id: id,
      name: name,
      logoUrl: logo_url,
      darkModeIcon: dark_mode_icon,
      lightModeIcon: light_mode_icon,
      totalModels: total_models || catalog_items.size,
    }
  end

  # Public: For use in audit log instrumentation, to describe what this record is.
  def event_prefix
    :model_publisher
  end

  # Public: For use in audit log instrumentation, to give basic information about this record when it's included
  # in another record's audit log event.
  def event_context(prefix: event_prefix)
    { prefix => name, "#{prefix}_id".to_sym => id }
  end

  private

  def set_logo_url
    self.logo_url ||= "/images/modules/marketplace/models/families/#{name.downcase}.svg"
  end
end
