# typed: true
# frozen_string_literal: true

class ModelsByok::CustomModel < ApplicationRecord::Domain::GitHubModels
  include DefaultAndCustomModels::IModel
  include Instrumentation::Model

  REGISTRY = "custom"

  belongs_to :custom_key, class_name: "ModelsByok::CustomKey", inverse_of: :custom_models, required: true

  has_one :organization, through: :custom_key, inverse_of: :custom_models, disable_joins: true

  before_destroy :verify_no_rules
  before_validation :set_name_from_slug

  validates :name, presence: true, length: { maximum: 60 }, uniqueness: { scope: :custom_key_id }
  validates :slug, presence: true, uniqueness: { scope: :custom_key_id }
  validates :slug, unless: :azureai?, length: { maximum: 80 }
  validates :slug, if: :azureai?, length: { minimum: 2, maximum: 64 },
    format: {
      with: /\A[a-zA-Z0-9._-]+\z/,
      message: "must be alphanumeric, can include underscores, hyphens, and periods",
    }

  has_many :organization_access_rules, class_name: "GitHubModels::OrganizationAccessRule", inverse_of: :custom_model

  after_commit :instrument_creation_event, on: :create
  after_commit :instrument_update_event, on: :update
  after_destroy_commit :instrument_deletion_event

  scope :alphabetical, -> { order(:name) }
  scope :for_org, ->(org_or_id) { joins(:custom_key).merge(ModelsByok::CustomKey.for_org(org_or_id)) }
  scope :newest_first, -> { order(created_at: :desc) }
  scope :recently_edited_first, -> { order(updated_at: :desc) }
  scope :for_custom_key, ->(custom_key_or_id) { where(custom_key_id: custom_key_or_id) }
  scope :enabled_for_copilot_chat, -> { where(copilot_chat_enabled: true) }

  # Public: Set the current user for audit logging purposes, when modifying the custom model.
  sig { params(value: T.nilable(User)).void }
  def actor=(value)
    self.custom_key&.actor = value
  end

  # Public: For use in audit log instrumentation, to describe what this record is.
  sig { override.returns(Symbol) }
  def event_prefix
    :custom_model
  end

  # Public: For use in audit log instrumentation, to give basic information about this record when it's included
  # in another record's audit log event.
  def event_context(prefix: event_prefix)
    { prefix => name, "#{prefix}_slug".to_sym => slug, "#{prefix}_id".to_sym => id }
  end

  def event_payload
    payload = { event_prefix => self, :copilot_chat_enabled => copilot_chat_enabled, :actor => actor }
    custom_key = self.custom_key
    payload[custom_key.event_prefix] = custom_key if custom_key
    organization = self.organization
    payload[organization.event_prefix] = organization if organization
    payload
  end

  # Public: Load many custom models based on ID, filtered to those belonging to the specified organization.
  sig { params(ids: T::Array[Integer], org: T.any(Organization, Integer)).returns(T::Array[ModelsByok::CustomModel]) }
  def self.find_many(ids, org:)
    for_org(org).where(id: ids).alphabetical.to_a
  end

  sig { returns T.nilable(String) }
  def custom_key_name
    custom_key&.name
  end

  sig { params(custom_model_a: ModelsByok::CustomModel, custom_model_b: ModelsByok::CustomModel).returns(Integer) }
  def self.key_and_name_sort(custom_model_a, custom_model_b)
    if custom_model_a.custom_key_id == custom_model_b.custom_key_id
      custom_model_a.name.downcase <=> custom_model_b.name.downcase
    else
      GitHub::PrefillAssociations.prefill_associations([custom_model_a, custom_model_b], :custom_key)
      custom_model_a.custom_key_name&.downcase <=> custom_model_b.custom_key_name&.downcase
    end
  end

  sig { override.params(user: T.nilable(User)).returns(T::Boolean) }
  def readable_by?(user)
    return false unless user

    organization = self.organization
    return false unless organization

    organization.member?(user)
  end

  sig { returns ModelsByok::Types::CustomModel }
  def to_h
    {
      id: id,
      name: logical_name,
      slug: slug,
      customKeyId: custom_key_id,
      enabled: {
        copilot: copilot_chat_enabled,
        models: organization_access_policy&.model_allowed?(self) || false,
      },
    }
  end

  sig { returns ModelsByok::Types::SelectorCustomModel }
  def to_selector_model
    ModelsByok::Types::SelectorCustomModel.new(
      id: id,
      slug: slug,
      name: logical_name,
      selected: true,
      # CreatedAt is the created date of the providers' model, not the timestamp of our CustomModel entity.
      # TODO: We should properly track that value somewhere
      createdAt: nil,
    )
  end

  sig { override.returns(String) }
  def logo_url
    custom_key&.logo_url || "/images/modules/marketplace/models/logo-github.svg"
  end

  # Public: Override ApplicationRecord::Base#reset_memoized_attributes to make sure that we clear memoization
  # variables on reload.
  sig { void }
  def reset_memoized_attributes
    remove_instance_variable(:@capabilities) if defined?(@capabilities)
  end

  sig { override.returns(String) }
  def task
    "chat-completion" # Until we have capabilities, all custom models support only chat-completion
  end

  sig { returns T::Boolean }
  def chat_completion?
    task == "chat-completion"
  end

  sig { returns DefaultAndCustomModels::Capabilities }
  def capabilities
    @capabilities ||= DefaultAndCustomModels::Capabilities.new(model_name: slug)
  end

  sig { returns T::Boolean }
  def restricted?
    capabilities.restricted?
  end

  # Public: Check if this model supports streaming responses.
  sig { returns T::Boolean }
  def supports_streaming?
    capabilities.supports_streaming?
  end

  # Public: Check if this model supports structured output.
  sig { returns T::Boolean }
  def supports_structured_output?
    capabilities.supports_structured_output?
  end

  sig { returns T::Boolean }
  def supports_token_counting?
    false
  end

  sig { returns T::Boolean }
  def supports_json_schema_structured_output?
    capabilities.supports_json_schema_structured_output?
  end

  sig { override.returns(String) }
  def friendly_name
    name
  end

  sig { override.returns(String) }
  def original_name
    slug
  end

  sig { override.returns(DefaultAndCustomModels::Types::Model) }
  def to_model
    custom_key_name = self.custom_key_name || "custom_key_#{custom_key_id}"
    {
      id: id.to_s,
      name: slug,
      friendly_name: friendly_name,
      original_name: original_name,
      publisher: custom_key_name,
      publisherDisplayName: nil,
      publisherSlug: custom_key_name,
      registry: registry,
      summary: "", # TODO Check this
      task: task,
      dark_mode_icon: nil,
      light_mode_icon: nil,
      logo_url: logo_url,
      isRestricted: false,
      capabilities: {
        jsonSchemaStructuredOutput: supports_json_schema_structured_output?,
        streaming: supports_streaming?,
        streamingOptions: false,
        structuredOutput: supports_structured_output?,
        tokenCounting: supports_token_counting?,
      },
      license: "",
      description: "",
      model_version: "",
      notes: "",
      popularity: nil,
      tags: [],
      rate_limit_tier: nil,
      supported_languages: [],
      max_output_tokens: nil,
      max_input_tokens: nil,
      training_data_date: nil,
      evaluation: nil,
      license_description: nil,
      supported_input_modalities: [],
      supported_output_modalities: [],
      isBillable: nil,
      isCustom: true,
    }
  end

  sig { override.returns(String) }
  def registry
    REGISTRY
  end

  sig { override.returns(DefaultAndCustomModels::Types::ModelSchema) }
  def to_schema
    catalog_model = self.catalog_model
    return catalog_model.to_schema if catalog_model

    # Hardcoded for now, but we will make this dynamic in the future.
    {
      examples: [],
      sampleInputs: [],
      inputs: [],
      outputs: [],
      fixedParameters: [],
      capabilities: {},
      type: "",
      version: "",
      behavior: nil,
      parameters: [
        {
          key: "top_p",
          friendlyName: "Top P",
          description: "Controls text diversity by selecting the most probable words until a set " \
            "probability is reached.",
          type: "number",
          payloadPath: "top_p",
          default: 1,
          max: 1,
          min: 0.01,
          required: false
        },
        {
          key: "temperature",
          friendlyName: "Temperature",
          description: "Controls randomness in the response, use lower to be more deterministic.",
          type: "number",
          payloadPath: "temperature",
          default: 1,
          max: 1,
          min: 0,
          required: false
        }
      ],
    }
  end

  sig { override.returns(DefaultAndCustomModels::Types::RepoModel) }
  def to_repository_model
    custom_key_name = self.custom_key_name || "custom_key_#{custom_key_id}"
    {
      id: id.to_s,
      name: slug,
      friendly_name: friendly_name,
      original_name: original_name,
      publisher: custom_key_name,
      publisherDisplayName: nil,
      publisherSlug: custom_key_name,
      registry: registry,
      summary: "", # TODO Check this
      task: task,
      dark_mode_icon: nil,
      light_mode_icon: nil,
      logo_url: logo_url,
      isRestricted: false,
      capabilities: {
        jsonSchemaStructuredOutput: supports_json_schema_structured_output?,
        streaming: supports_streaming?,
        streamingOptions: false,
        structuredOutput: supports_structured_output?,
        systemPrompt: false,
        tokenCounting: supports_token_counting?,
        modelInputSchemaParameters: to_schema[:parameters],
      },
      isCustom: true,
    }
  end

  private

  delegate :actor, to: :custom_key, allow_nil: true

  sig { returns T.nilable(GitHubModels::OrganizationAccessPolicy) }
  def organization_access_policy
    organization = self.organization
    return unless organization
    GitHubModels::OrganizationAccessPolicy.new(org: organization)
  end

  sig { returns T.nilable(GitHubModels::IModel) }
  def catalog_model
    return nil unless custom_key&.openai?
    slug = "azure-openai/#{self.slug.to_param.gsub(/\./, "-")}"
    # OpenAI has model slugs that are stable enough we can attempt to map them to our catalog.
    GitHubModels.domain.models.find(slug: slug)
  end

  def verify_no_rules
    if organization_access_rules.any?
      errors.add(:base, "Organization access rules must be deleted first")
      throw :abort
    end
  end

  def instrument_creation_event
    # Audit log:
    instrument :create
  end

  def instrument_update_event
    extra_payload = {}
    unless name == name_before_last_save
      extra_payload["old_#{event_prefix}".to_sym] = name_before_last_save
    end
    unless copilot_chat_enabled == copilot_chat_enabled_before_last_save
      extra_payload[:old_copilot_chat_enabled] = copilot_chat_enabled_before_last_save
    end

    # Audit log:
    instrument :update, extra_payload
  end

  def instrument_deletion_event
    # Audit log:
    instrument :destroy
  end

  sig { returns T.nilable(String) }
  def logical_name
    name.eql?(slug) ? nil : name
  end

  def set_name_from_slug
    return if name.present?
    self.name = slug
  end

  sig { returns T.nilable(T::Boolean) }
  def azureai?
    custom_key&.azureai?
  end
end
