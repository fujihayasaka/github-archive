# typed: true
# frozen_string_literal: true

class GitHubModels::Publisher < ApplicationRecord::Domain::GitHubModels
  self.table_name = "models_publishers"

  before_validation :set_logo_url

  validates :name, presence: true, uniqueness: true, length: { maximum: 50 }
  validates_presence_of :logo_url

  has_many :organization_access_rules, class_name: "GitHubModels::OrganizationAccessRule",
    foreign_key: "models_publisher_id", inverse_of: :publisher

  has_many :models, class_name: "GitHubModels::Model", inverse_of: :models_publisher

  scope :alphabetical, -> { order(name: :asc) }
  scope :publicly_visible, -> { joins(:models).merge(GitHubModels::Model.publicly_visible).distinct }

  # Public: Get a hash mapping publisher IDs to a count of how many models are associated with the publisher.
  sig { params(models: T::Array[GitHubModels::IModel]).returns(T::Hash[Integer, Integer]) }
  def self.model_counts_by_id(models)
    models.each_with_object(Hash.new(0)) do |model, hash|
      hash[model.models_publisher_id] += 1
    end
  end

  # Public: Get a parameterized slug for a publisher name.
  sig { params(publisher_name: T.nilable(String)).returns(String) }
  def self.slug_for(publisher_name)
    publisher_name.to_s.parameterize
  end

  sig { params(total_models: T.nilable(Integer)).returns(GitHubModels::Types::Publisher) }
  def to_h(total_models: nil)
    display_name = self.display_name
    {
      id: id,
      name: name,
      displayName: name == display_name ? nil : display_name,
      logoUrl: logo_url,
      darkModeIcon: dark_mode_icon,
      lightModeIcon: light_mode_icon,
      totalModels: total_models || models.size,
    }
  end

  sig { params(name: String).returns(String) }
  def self.display_name_for(name)
    case name.downcase.strip
    when "deepseek" then "DeepSeek"
    when "mistral ai" then "Mistral"
    when "openai" then "Azure OpenAI Service"
    else
      name
    end
  end

  # Public: Controls how we present a publisher in Marketplace search filters and the playground.
  sig { returns String }
  def display_name
    self.class.display_name_for(name)
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
