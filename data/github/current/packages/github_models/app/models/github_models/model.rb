# typed: true
# frozen_string_literal: true

class GitHubModels::Model < ApplicationRecord::Domain::GitHubModels
  include GitHubModels::IModel

  serialize :tags, type: Array
  serialize :supported_languages, type: Array
  serialize :supported_input_modalities, type: Array
  serialize :supported_output_modalities, type: Array
  serialize :model_schema, coder: JSON

  self.table_name = "models"

  has_many :organization_access_rules, class_name: "GitHubModels::OrganizationAccessRule",
    foreign_key: :catalog_item_key, inverse_of: :model, primary_key: :slug

  has_one :models_multiplier, class_name: "GitHubModels::Multiplier", inverse_of: :model,
    foreign_key: :models_slug, primary_key: :slug, required: false

  belongs_to :models_publisher, class_name: "GitHubModels::Publisher", inverse_of: :models

  enum :visibility, {
    visible: 0,
    staffshipped: 1,
    hidden: 2,
    featured: 3,
  }

  enum :source, {
    azure_openai: 0
  }

  scope :publicly_visible, -> { visible.or(scoped.featured) }
  scope :recently_added, -> { order(created_at: :desc) }
  scope :popular, -> { order(popularity: :desc) }

  validates :original_name, :slug, presence: true, uniqueness: true
  validates :name, :original_name, :friendly_name, :license, :rate_limit_tier, length: { maximum: 60 }
  validates :version, :task, length: { maximum: 30 }

  after_commit :synchronize_search_index

  SLUG_SEPARATOR = "/"

  # Public: Look up multiple models by their external-facing slugs (e.g., "openai/gpt-4o"). If given a list of
  # models, will return a subset of those, otherwise will search all existing models.
  sig do
    params(external_slug_or_slugs: T.any(String, T::Array[String]), models: T.nilable(T::Array[GitHubModels::Model]))
      .returns(T::Array[GitHubModels::Model])
  end
  def self.with_external_slug(external_slug_or_slugs, models: nil)
    external_slugs = Array.wrap(external_slug_or_slugs).compact
    models ||= all.to_a
    slugs = external_slugs.map { |external_slug| slug_from_external_slug(external_slug, models: models) }.to_set
    models.select { |model| slugs.include?(model.slug) }
  end

  sig { params(registry: String, name: String).returns(String) }
  def self.slug_for(registry:, name:)
    "#{registry}#{SLUG_SEPARATOR}#{name}"
  end

  # Public: Given an external-facing slug for a model (e.g., "mistral-ai/mistral-nemo"), get the corresponding
  # internal slug (e.g., "azureml-mistral/Mistral-Nemo"). Pass an optional list of models to choose from if known,
  # otherwise all existing models will be searched.
  sig do
    params(
      external_slug: T.nilable(String),
      models: T.nilable(T::Array[GitHubModels::Model])
    ).returns(T.nilable(String))
  end
  def self.slug_from_external_slug(external_slug, models: nil)
    return if external_slug.blank? || !external_slug.include?(SLUG_SEPARATOR)
    downcased_external_slug = external_slug.downcase
    publisher_slug, original_name = downcased_external_slug.split(SLUG_SEPARATOR, 2)
    models ||= GitHubModels::Model.where(original_name: original_name).to_a
    models_by_original_name = models.index_by(&:original_name)
    model = models_by_original_name[original_name]
    return if model.nil? || model.publisher_slug.downcase != publisher_slug
    model.slug
  end

  sig { params(slug: String).returns(T.nilable([String, String])) }
  def self.registry_and_name_from_slug(slug)
    parts = slug.split(SLUG_SEPARATOR)
    return unless parts.size == 2

    registry = T.must(parts[0])
    name = T.must(parts[1])
    [registry, name]
  end

  sig { params(model_order: GitHubModels::ModelOrder).returns(ActiveRecord::Relation) }
  def self.order_by(model_order)
    case model_order
    when GitHubModels::ModelOrder::Slug
      order(:slug)
    when GitHubModels::ModelOrder::RecentlyAdded
      recently_added
    when GitHubModels::ModelOrder::Popular
      popular
    else
      T.absurd(model_order)
    end
  end

  sig { returns T::Array[String] }
  def self.publicly_visible_tags
    publicly_visible.pluck(:tags).flatten.uniq.sort
  end

  sig { override.returns(String) }
  def downcased_external_slug
    "#{publisher_slug}#{SLUG_SEPARATOR}#{original_name}".downcase
  end

  # Public: Override ApplicationRecord::Base#reset_memoized_attributes to make sure that we clear memoization
  # variables on reload.
  sig { void }
  def reset_memoized_attributes
    remove_instance_variable(:@parsed_value) if defined?(@parsed_value)
    remove_instance_variable(:@model_id) if defined?(@model_id)
    remove_instance_variable(:@dark_mode_icon) if defined?(@dark_mode_icon)
    remove_instance_variable(:@light_mode_icon) if defined?(@light_mode_icon)
    remove_instance_variable(:@registry) if defined?(@registry)
    remove_instance_variable(:@capabilities) if defined?(@capabilities)
  end

  def parsed_value
    return @parsed_value if defined?(@parsed_value)
    result = value.is_a?(String) ? JSON.parse(value) : value
    @parsed_value = (result.is_a?(Hash) ? result.deep_symbolize_keys : result) || {}
  end

  sig do
    params(
      registry: String,
      model_name: String,
      version: String,
      ai_studio_client: T.nilable(GitHubModels::AzureAiStudioClient),
      schema_client: T.nilable(GitHubModels::AzureAiModelSchemaClient)
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def self.fetch_value(registry:, model_name:, version:, ai_studio_client: nil, schema_client: nil)
    ai_studio_client ||= GitHubModels::AzureAiStudioClient.new
    schema_client ||= GitHubModels::AzureAiModelSchemaClient.new
    model = ai_studio_client.fetch_model_details(registry: registry, model: model_name, version: version)
    schema = schema_client.fetch_model_schema(registry: registry, model: model_name)
    { model: model, schema: schema }
  end

  def value=(new_value)
    super(new_value)
    reset_memoized_attributes
  end

  sig { override.returns(T::Boolean) }
  def chat_completion?
    task = to_model[:task]
    task == "chat-completion"
  end

  sig { override.returns(DefaultAndCustomModels::Types::Model) }
  def to_model
    hash = parsed_value[:model]
    publisher_display_name = self.publisher_display_name
    hash = hash.slice(
      :id, :registry, :name, :original_name, :friendly_name, :task, :publisher, :license, :description,
      :summary, :model_version, :notes, :popularity, :tags, :rate_limit_tier, :supported_languages,
      :max_output_tokens, :max_input_tokens, :training_data_date, :logo_url, :dark_mode_icon, :light_mode_icon,
      :evaluation, :license_description, :supported_input_modalities, :supported_output_modalities
    ).merge(publisherSlug: publisher_slug)
    hash[:publisherDisplayName] = hash[:publisher] == publisher_display_name ? nil : publisher_display_name
    hash[:capabilities] = {
      jsonSchemaStructuredOutput: supports_json_schema_structured_output?,
      tokenCounting: supports_token_counting?,
      streaming: supports_streaming?,
      streamingOptions: supports_streaming_options?,
      structuredOutput: supports_structured_output?,
    }
    hash[:isRestricted] = restricted?
    hash[:isBillable] = billable?
    hash[:isCustom] = false
    hash
  end

  sig { override.returns(GitHubModels::Types::FeaturedModel) }
  def to_featured_model
    featured_model = to_model.slice(:id, :registry, :name, :friendly_name, :publisher, :summary, :logo_url,
      :light_mode_icon, :dark_mode_icon)
    T.cast(featured_model, GitHubModels::Types::FeaturedModel)
  end

  sig { override.returns(DefaultAndCustomModels::Types::RepoModel) }
  def to_repository_model
    repo_model = to_model.slice(:dark_mode_icon, :friendly_name, :id, :light_mode_icon, :logo_url, :name,
      :original_name, :publisher, :registry, :summary, :task, :publisherSlug, :capabilities, :isRestricted, :isCustom)
    model_schema = to_schema
    repo_model[:capabilities][:systemPrompt] = model_schema.dig(:capabilities, :systemPrompt) || false
    repo_model[:capabilities][:modelInputSchemaParameters] = model_schema.dig(:parameters) || []

    T.cast(repo_model, DefaultAndCustomModels::Types::RepoModel)
  end

  sig { returns T::Boolean }
  def supports_token_counting?
    capabilities.supports_token_counting?
  end

  # Public: Check if this model supports streaming responses. For user-specific checks, see
  # GitHubModels::User#streaming_feature_enabled_for_model?.
  sig { returns T::Boolean }
  def supports_streaming?
    capabilities.supports_streaming?
  end

  # Public: Check if this model supports setting options for streaming responses.
  sig { returns T::Boolean }
  def supports_streaming_options?
    publisher_matches?("openai")
  end

  sig { returns T::Boolean }
  def supports_json_schema_structured_output?
    capabilities.supports_json_schema_structured_output?
  end

  # Public: Check if this model supports structured output.
  sig { returns T::Boolean }
  def supports_structured_output?
    capabilities.supports_structured_output?
  end

  sig { returns DefaultAndCustomModels::Capabilities }
  def capabilities
    @capabilities ||= DefaultAndCustomModels::Capabilities.new(
      model_name: original_name,
      published_by_mistral_ai: publisher_matches?("mistral ai"),
      published_by_openai: publisher_matches?("openai"),
      published_by_xai: publisher_matches?("xai"),
    )
  end

  sig { override.returns(T::Boolean) }
  def restricted?
    capabilities.restricted?
  end

  sig { returns T::Boolean }
  def billable?
    models_multiplier.present?
  end

  sig { override.returns(T.nilable(GitHubModels::Types::OrganizationAccessPolicyShowModel)) }
  def to_organization_access_policy_show_model
    registry = self.registry
    name = self.name
    return unless registry && name && models_publisher_id

    {
      key: slug,
      registry: registry,
      friendlyName: friendly_name.presence || name,
      name: name,
      publisherId: T.must(models_publisher_id),
    }
  end

  sig { override.returns(DefaultAndCustomModels::Types::ModelSchema) }
  def to_schema
    parsed_value[:schema]
  end

  sig { override.returns(T.nilable(String)) }
  def external_id
    parsed_value.dig(:model, :id)
  end

  sig { override.returns(T.nilable(String)) }
  def logo_url
    parsed_value.dig(:model, :logo_url)
  end

  sig { override.returns(T.nilable(String)) }
  def dark_mode_icon
    return @dark_mode_icon if defined?(@dark_mode_icon)
    @dark_mode_icon = parsed_value.dig(:model, :dark_mode_icon)
  end

  sig { override.returns(T.nilable(String)) }
  def light_mode_icon
    return @light_mode_icon if defined?(@light_mode_icon)
    @light_mode_icon = parsed_value.dig(:model, :light_mode_icon)
  end

  sig { override.params(dark_mode: T::Boolean).returns(T.nilable(String)) }
  def icon_src(dark_mode:)
    icon_url = dark_mode ? dark_mode_icon : light_mode_icon
    return "data:image/svg+xml;base64,#{icon_url}" if icon_url.present?
    logo_url
  end

  sig { override.returns(T.nilable(String)) }
  def publisher
    parsed_value.dig(:model, :publisher)
  end

  sig { returns String }
  def publisher_slug
    return @publisher_slug if defined?(@publisher_slug)
    @publisher_slug = GitHubModels::Publisher.slug_for(publisher)
  end

  sig { returns(T.nilable(String)) }
  def publisher_display_name
    publisher = self.publisher
    return unless publisher
    GitHubModels::Publisher.display_name_for(publisher)
  end

  sig { override.params(publisher_name: T.nilable(String)).returns(T::Boolean) }
  def publisher_matches?(publisher_name)
    [publisher&.downcase, publisher_slug].include?(publisher_name&.downcase)
  end

  sig { override.returns(T.nilable(String)) }
  def registry
    return @registry if defined?(@registry)
    @registry = parsed_value.dig(:model, :registry)
  end

  sig { override.returns(T::Array[String]) }
  def catalog_capabilities
    parsed_value.dig(:model, :model_capabilities) || []
  end

  # Public: The relative URL to view the model's details on GitHub.
  sig { override.returns(String) }
  def details_path
    "/marketplace/models/#{registry}/#{name}"
  end

  # Public: Returns a mapping from a model's unique identifier to whether or not its visible to the given user.
  sig { params(user: T.nilable(User)).returns(T::Hash[String, T::Boolean]) }
  def self.visibility_map(user)
    all.each_with_object({}) do |model, hash|
      case model.visibility
      when "visible"
        hash[model.slug] = true
      when "staffshipped"
        hash[model.slug] = !!user&.employee?
      when "hidden"
        hash[model.slug] = false
      end
    end
  end

  sig { params(user: T.nilable(User), registry: String, name: String).returns(T::Boolean) }
  def self.can_view?(user:, registry:, name:)
    model = find_by(slug: slug_for(registry: registry, name: name))
    return false if model.nil?

    model.readable_by?(user)
  end

  sig { override.params(user: T.nilable(User)).returns(T::Boolean) }
  def readable_by?(user)
    case visibility
    when "visible", "featured"
      true
    when "staffshipped"
      !!user&.employee?
    when "hidden"
      false
    end
  end

  # Public: For use in audit log instrumentation, to describe what this record is.
  sig { override.returns(Symbol) }
  def event_prefix
    :model
  end

  # Public: For use in audit log instrumentation, to give basic information about this record when it's included
  # in another record's audit log event.
  def event_context(prefix: event_prefix)
    { prefix => friendly_name, "#{prefix}_key".to_sym => slug }
  end

  private

  # Private: Synchronize this model with its representation in the search
  # index. All existing models that are not delisted get indexed.
  def synchronize_search_index
    if destroyed?
      RemoveFromSearchIndexJob.perform_later("azure_model", id)
    else
      Search.add_to_search_index("azure_model", id)
    end

    self
  end
end
