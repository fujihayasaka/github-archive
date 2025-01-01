# typed: true
# frozen_string_literal: true

class ModelsByok::CustomKey < ApplicationRecord::Domain::GitHubModels
  include Instrumentation::Model

  KREDZ_KEY_PREFIX = "custom_key_"
  ENCRYPTION_KEY_NAME = ::Platform::EncryptionKeys::BYOK_CUSTOM_MODELS_SECRETS

  # Keep in sync with `validHostnames` in
  # ui/packages/models-byok-settings/components/providers/azureai/AzureAIFields.tsx
  VALID_AZURE_OPENAI_HOSTNAME = "openai.azure.com".freeze
  VALID_AZURE_HOSTNAMES = [
    "models.ai.azure.com",
    "inference.ml.azure.com",
    VALID_AZURE_OPENAI_HOSTNAME,
    "services.ai.azure.com",
    "cognitiveservices.azure.com"
  ].freeze

  belongs_to :organization, required: true, inverse_of: :models_custom_keys

  has_many :custom_models, class_name: "ModelsByok::CustomModel", inverse_of: :custom_key
  has_many :organization_access_rules, class_name: "GitHubModels::OrganizationAccessRule", inverse_of: :custom_key

  # Used to temporarily hold the current user, for use in instrumentation:
  sig { returns T.nilable(User) }
  attr_accessor :actor

  validates :name, presence: true, length: { maximum: 60 }, uniqueness: { scope: :organization_id },
    format: {
      with: ::GitHub::KredzClient::Credz::SECRET_KEY_VALID_CHAR_REGEX,
      message: "can only contain letters, numbers, or underscores, and must start with a letter or underscore",
    }

  before_destroy :verify_no_rules_or_models
  before_validation :setup_kredz_key, on: :create
  validates :kredz_key, presence: true, length: { maximum: 60 }, uniqueness: { scope: :organization_id }

  validate :deployment_url_only_for_azure_ai

  after_commit :instrument_creation_event, on: :create
  after_commit :instrument_update_event, on: :update
  after_destroy_commit :instrument_deletion_event
  after_destroy_commit :cleanup_secrets

  scope :for_org, ->(org_or_id) { where(organization_id: org_or_id) }
  scope :newest_first, -> { order(created_at: :desc) }

  enum :provider, {
    openai: 0,
    azureai: 1,
  }

  accepts_nested_attributes_for :custom_models

  # Public: Get a hash mapping custom key IDs to a count of how many models are associated with the custom key.
  sig { params(models: T::Array[ModelsByok::CustomModel]).returns(T::Hash[Integer, Integer]) }
  def self.model_counts_by_id(models)
    models.each_with_object(Hash.new(0)) do |model, hash|
      hash[model.custom_key_id] += 1
    end
  end

  # Public: For use in audit log instrumentation, to describe what this record is.
  sig { returns Symbol }
  def event_prefix
    :custom_key
  end

  # Public: For use in audit log instrumentation, to give basic information about this record when it's included
  # in another record's audit log event.
  def event_context(prefix: event_prefix)
    { prefix => name, "#{prefix}_provider".to_sym => provider, "#{prefix}_id".to_sym => id }
  end

  def event_payload
    payload = { event_prefix => self, :deployment_url => deployment_url, :actor => actor }
    organization = self.organization
    payload[organization.event_prefix] = organization if organization
    payload
  end

  sig { params(total_models: T.nilable(Integer)).returns(ModelsByok::Types::CustomKey) }
  def to_h(total_models: nil)
    {
      id: id,
      name: name,
      provider: provider,
      totalModels: total_models || custom_models.size,
      deploymentUrl: azureai? ? deployment_url : nil, # Only for AzureAI provider
    }
  end

  sig { params(actor: ::User, api_key: String, app: Integration).returns(T::Boolean) }
  def create_secret(actor:, api_key:, app: self.class.integration_app)
    organization = self.organization
    return false unless organization

    Secrets.create(
      name: kredz_key,
      owner: organization,
      actor: actor,
      value: self.class.embed_value(api_key, owner: organization),
      app: app,
      visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_ALL_REPOS,
    )

    true
  rescue ::Secrets::Error, ArgumentError => e
    log_secrets_error(e, action: "create", actor_id: actor.id)
    false
  end

  sig { params(actor: ::User, app: Integration).returns(T.nilable(String)) }
  def fetch_secret(actor:, app: self.class.integration_app)
    organization = self.organization
    return nil unless organization

    Secrets.fetch(
      name: kredz_key,
      owner: organization,
      actor: actor,
      app: app,
      include_value: true,
    ).credential.value
  rescue ::Secrets::Error, ArgumentError => e
    log_secrets_error(e, action: "fetch", actor_id: actor.id)
    nil
  end

  sig { params(actor: ::User, api_key: String, app: Integration).returns(T::Boolean) }
  def update_secret(actor:, api_key:, app: self.class.integration_app)
    organization = self.organization
    return false unless organization

    Secrets.update(
      name: kredz_key,
      owner: organization,
      actor: actor,
      value: self.class.embed_value(api_key, owner: organization),
      app: app,
      visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_ALL_REPOS,
    )

    true
  rescue ::Secrets::Error, ArgumentError => e
    log_secrets_error(e, action: "update", actor_id: actor.id)
    false
  end

  sig { returns String }
  def self.generate_kredz_key
    "#{KREDZ_KEY_PREFIX}#{SecureRandom.hex(8)}"
  end

  sig { params(owner: Organization).returns([Integer, String]) }
  def self.encryption_public_key(owner)
    Secrets.github_public_key(owner: owner, key_name: ENCRYPTION_KEY_NAME)
  end

  sig { params(encrypted_value: String, owner: Organization).returns(String) }
  def self.decrypt_secret(encrypted_value, owner:)
    decoded_value = Base64.strict_decode64(encrypted_value)
    earthsmoke_key = DietEarthsmoke::Key.new(ENCRYPTION_KEY_NAME)
    earthsmoke_key.open(decoded_value, scope: owner.next_global_id)
  end

  sig { params(value: String, owner: Organization).returns(String) }
  def self.embed_value(value, owner:)
    key_id, _ = encryption_public_key(owner)
    value = Secrets.embed(key_id, Base64.strict_decode64(value))
    Base64.strict_encode64(value)
  end

  sig { returns Integration }
  def self.integration_app
    Apps::Privileged.integration(:byok_custom_models)
  end

  sig do
    params(fresh_provider_models: T::Array[ModelsByok::Types::SelectorCustomModel])
      .returns(T::Array[ModelsByok::Types::SelectorCustomModel])
  end
  def reconcile_custom_models_with_provider(fresh_provider_models)
    result = T.let([], T::Array[ModelsByok::Types::SelectorCustomModel])
    fresh_provider_models_by_slug = fresh_provider_models.index_by(&:slug)

    # Sort by updated_at in descending order, so latest_updated_at is simply the first one.
    # TODO: To do this properly, we should consider storing a "latest retrieval time". On this key.
    custom_models = self.custom_models.recently_edited_first
    latest_updated_at = T.let(custom_models.first&.updated_at, T.nilable(Time))

    # Process existing custom models
    custom_models.each do |custom_model|
      provider_model = fresh_provider_models_by_slug.delete(custom_model.slug)
      item = custom_model.to_selector_model
      item.deprecated = true unless provider_model # exists only in current custom_models — mark as deprecated
      result << item
    end

    # Add new new models
    fresh_provider_models_by_slug.each_value do |provider_model|
      provider_created_at = provider_model.createdAt
      provider_model.fresh = latest_updated_at && provider_created_at && provider_created_at > latest_updated_at
      result << provider_model
    end

    result.sort_by do |model|
      [
        model.deprecated ? 0 : 1, # Deprecated models at the top
        model.selected ? 0 : 1,   # then selected models
        model.name || "",         # then by name
        model.slug                # by slug
      ]
    end
  end

  sig { returns String }
  def logo_url
    case provider
    when "azureai"
      "/images/modules/marketplace/models/logo-azure.svg"
    when "openai"
      "/images/modules/marketplace/models/families/openai.svg"
    else
      "/images/modules/marketplace/models/logo-github.svg"
    end
  end

  private

  def instrument_creation_event
    # Audit log:
    instrument :create
  end

  def instrument_update_event
    extra_payload = {}
    unless name == name_before_last_save
      extra_payload["old_#{event_prefix}".to_sym] = name_before_last_save
    end
    unless deployment_url == deployment_url_before_last_save
      extra_payload[:old_deployment_url] = deployment_url_before_last_save
    end

    # Audit log:
    instrument(:update, extra_payload) unless extra_payload.empty?
  end

  def instrument_deletion_event
    # Audit log:
    instrument :destroy
  end

  def verify_no_rules_or_models
    any_custom_models = custom_models.any?
    any_rules = organization_access_rules.any?
    return unless any_custom_models || any_rules

    suffix = " must be deleted first"
    if any_custom_models && any_rules
      errors.add(:base, "Custom models and organization access rules#{suffix}")
    elsif any_custom_models
      errors.add(:base, "Custom models#{suffix}")
    else
      errors.add(:base, "Organization access rules#{suffix}")
    end

    throw :abort
  end

  def setup_kredz_key
    return if kredz_key.present?

    candidate_key = self.class.generate_kredz_key
    attempts = 0
    while attempts < 9 && self.class.for_org(organization_id).exists?(kredz_key: candidate_key)
      candidate_key = self.class.generate_kredz_key
      attempts += 1
    end

    self.kredz_key = candidate_key
  end

  def deployment_url_only_for_azure_ai
    if deployment_url.present? && !azureai?
      errors.add(:deployment_url, "can only be set for an Azure AI custom key")
    end

    if azureai?
      if deployment_url.blank?
        errors.add(:deployment_url, "must be set for an Azure AI custom key")
      else
        uri = URI.parse(deployment_url) rescue nil
        if uri.nil?
          errors.add(:deployment_url, "is not a valid URL")
        elsif VALID_AZURE_HOSTNAMES.none? { |h| uri.hostname&.downcase == h || uri.hostname&.downcase&.end_with?(".#{h}") }
          errors.add(:deployment_url, "must be a valid Azure AI endpoint")
        end
      end
    end
  end

  sig { void }
  def cleanup_secrets
    ModelsByok::CleanupSecretJob.perform_later(
      kredz_key_name: kredz_key,
      actor_id: actor&.id,
      org_id: organization_id,
    )
  end

  sig { params(e: StandardError, action: String, actor_id: Integer).void }
  def log_secrets_error(e, action:, actor_id:)
    GitHub.logger.error("Failed to #{action} secret for custom key", {
      "exception.type": e.class.name,
      "exception.message": e.message,
      "gh.organization.id": organization_id,
      "gh.actor.id": actor_id,
      "custom_key_name": name,
      "kredz_key": kredz_key,
    })
  end
end
