# typed: true
# frozen_string_literal: true

class GitHubModels::CatalogItem < ApplicationRecord::Domain::Integrations
  serialize :tags, type: Array
  serialize :supported_languages, type: Array
  serialize :supported_input_modalities, type: Array
  serialize :supported_output_modalities, type: Array
  serialize :schema, coder: JSON

  self.table_name = "azure_models_catalog_items"
  self.ignored_columns = %w(model_family)

  has_many :organization_access_rules, class_name: "GitHubModels::OrganizationAccessRule",
    foreign_key: :catalog_item_key, inverse_of: :catalog_item, primary_key: :key

  belongs_to :github_models_publisher, class_name: "GitHubModels::Publisher", inverse_of: :catalog_items

  enum :visibility, {
    visible: 0,
    staffshipped: 1,
    hidden: 2,
    featured: 3,
  }

  enum :source, {
    azure_openai: 0
  }

  validates :key, presence: true, uniqueness: true
  validates :guid, length: { maximum: 150 }
  validates :name, :original_name, :friendly_name, :license, :rate_limit_tier, length: { maximum: 60 }
  validates :model_version, :task, length: { maximum: 30 }

  # Public: Synchronize this action with its representation in the search
  # index. All existing actions that are not delisted get indexed.
  def synchronize_search_index(deleting: false)
    if deleting
      RemoveFromSearchIndexJob.perform_later("azure_model", self.id)
    else
      Search.add_to_search_index("azure_model", self.id)
    end

    self
  end

  KEY_SEPARATOR = "/"

  sig { params(registry: String, name: String).returns(String) }
  def self.key_for(registry:, name:)
    "#{registry}#{KEY_SEPARATOR}#{name}"
  end

  sig { params(key: String).returns(T.nilable([String, String])) }
  def self.registry_and_name_from_key(key)
    parts = key.split(KEY_SEPARATOR)
    return unless parts.size == 2

    registry = T.must(parts[0])
    name = T.must(parts[1])
    [registry, name]
  end

  # Public: Override ApplicationRecord::Base#reset_memoized_attributes to make sure that we clear memoization
  # variables on reload.
  sig { void }
  def reset_memoized_attributes
    remove_instance_variable(:@parsed_value) if defined?(@parsed_value)
    remove_instance_variable(:@name) if defined?(@name)
    remove_instance_variable(:@model_id) if defined?(@model_id)
    remove_instance_variable(:@friendly_name) if defined?(@friendly_name)
    remove_instance_variable(:@task) if defined?(@task)
    remove_instance_variable(:@dark_mode_icon) if defined?(@dark_mode_icon)
    remove_instance_variable(:@light_mode_icon) if defined?(@light_mode_icon)
    remove_instance_variable(:@registry) if defined?(@registry)
    remove_instance_variable(:@tags) if defined?(@tags)
  end

  def parsed_value
    return @parsed_value if defined?(@parsed_value)
    result = value.is_a?(String) ? JSON.parse(value) : value
    @parsed_value = (result.is_a?(Hash) ? result.deep_symbolize_keys : result) || {}
  end

  def value=(new_value)
    super(new_value)
    reset_memoized_attributes
  end

  sig { returns GitHubModels::Types::Model }
  def to_model
    hash = parsed_value[:model]
    hash.slice(:id, :registry, :name, :original_name, :friendly_name, :task, :publisher, :license, :description,
      :summary, :model_version, :notes, :popularity, :tags, :rate_limit_tier, :supported_languages,
      :max_output_tokens, :max_input_tokens, :training_data_date, :logo_url, :dark_mode_icon, :light_mode_icon,
      :evaluation, :license_description, :supported_input_modalities, :supported_output_modalities)
  end

  sig { returns T.nilable(GitHubModels::Types::OrganizationAccessPolicyShowModel) }
  def to_organization_access_policy_show_model
    registry = self.registry
    name = self.name
    publisher_id = github_models_publisher_id
    return unless registry && name && publisher_id

    {
      key: key,
      registry: registry,
      friendlyName: friendly_name.presence || name,
      name: name,
      publisherId: publisher_id,
    }
  end

  sig { returns GitHubModels::Types::ModelSchema }
  def to_schema
    parsed_value[:schema]
  end

  sig { returns T.nilable(String) }
  def rate_limit_tier
    parsed_value.dig(:model, :rate_limit_tier)
  end

  sig { returns T.nilable(String) }
  def license
    parsed_value.dig(:model, :license)
  end

  sig { returns T.nilable(String) }
  def license_description
    parsed_value.dig(:model, :license_description)
  end

  sig { returns T.nilable(String) }
  def notes
    parsed_value.dig(:model, :notes)
  end

  sig { returns T.nilable(String) }
  def description
    parsed_value.dig(:model, :description)
  end

  sig { returns T.nilable(String) }
  def name
    return @name if defined?(@name)
    @name = parsed_value.dig(:model, :name)
  end

  sig { returns T.nilable(Integer) }
  def max_output_tokens
    parsed_value.dig(:model, :max_output_tokens)
  end

  sig { returns T.nilable(Integer) }
  def max_input_tokens
    parsed_value.dig(:model, :max_input_tokens)
  end

  sig { returns T.nilable(String) }
  def model_id
    return @model_id if defined?(@model_id)
    @model_id = parsed_value.dig(:model, :id)
  end

  sig { returns T.nilable(String) }
  def friendly_name
    return @friendly_name if defined?(@friendly_name)
    @friendly_name = parsed_value.dig(:model, :friendly_name)
  end

  sig { returns T.nilable(String) }
  def task
    return @task if defined?(@task)
    @task = parsed_value.dig(:model, :task)
  end

  sig { returns T.nilable(String) }
  def logo_url
    parsed_value.dig(:model, :logo_url)
  end

  sig { returns T.nilable(String) }
  def dark_mode_icon
    return @dark_mode_icon if defined?(@dark_mode_icon)
    @dark_mode_icon = parsed_value.dig(:model, :dark_mode_icon)
  end

  sig { returns T.nilable(String) }
  def light_mode_icon
    return @light_mode_icon if defined?(@light_mode_icon)
    @light_mode_icon = parsed_value.dig(:model, :light_mode_icon)
  end

  sig { params(dark_mode: T::Boolean).returns(T.nilable(String)) }
  def icon_src(dark_mode:)
    icon_url = dark_mode ? dark_mode_icon : light_mode_icon
    return "data:image/svg+xml;base64,#{icon_url}" if icon_url.present?
    logo_url
  end

  sig { returns T.nilable(String) }
  def publisher
    parsed_value.dig(:model, :publisher)
  end

  sig { returns T.nilable(String) }
  def registry
    return @registry if defined?(@registry)
    @registry = parsed_value.dig(:model, :registry)
  end

  sig { returns T::Array[String] }
  def supported_input_modalities
    parsed_value.dig(:model, :supported_input_modalities) || []
  end

  sig { returns T::Array[String] }
  def supported_output_modalities
    parsed_value.dig(:model, :supported_output_modalities) || []
  end

  sig { returns T::Array[String] }
  def tags
    return @tags if defined?(@tags)
    @tags = parsed_value.dig(:model, :tags) || []
  end

  sig { returns T::Array[String] }
  def supported_languages
    parsed_value.dig(:model, :supported_languages) || []
  end

  sig { returns T.nilable(String) }
  def summary
    parsed_value.dig(:model, :summary)
  end

  # Public: The relative URL to view the model's details on GitHub.
  sig { returns String }
  def details_path
    "/marketplace/models/#{registry}/#{name}"
  end

  sig { params(user: T.nilable(User)).returns(T::Hash[String, T::Boolean]) }
  def self.visibility_map(user)
    GitHubModels::CatalogItem.all.each_with_object({}) do |item, hash|
      case item.visibility
      when "visible"
        hash[item.key] = true
      when "staffshipped"
        hash[item.key] = !!user&.employee?
      when "hidden"
        hash[item.key] = false
      end
    end
  end

  sig { params(user: T.nilable(User), registry: String, name: String).returns(T::Boolean) }
  def self.can_view?(user:, registry:, name:)
    catalog_item = find_by(key: key_for(registry: registry, name: name))
    return false if catalog_item.nil?

    case catalog_item.visibility
    when "visible", "featured"
      true
    when "staffshipped"
      !!user&.employee?
    when "hidden"
      false
    end
  end

  # Public: For use in audit log instrumentation, to describe what this record is.
  def event_prefix
    :model
  end

  # Public: For use in audit log instrumentation, to give basic information about this record when it's included
  # in another record's audit log event.
  def event_context(prefix: event_prefix)
    { prefix => friendly_name, "#{prefix}_key".to_sym => key }
  end
end
