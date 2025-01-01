# typed: true
# frozen_string_literal: true

class ModelsByok::CustomKey < ApplicationRecord::Domain::GitHubModels
  KREDZ_KEY_PREFIX = "custom_key_"
  ENCRYPTION_KEY_NAME = ::Platform::EncryptionKeys::BYOK_CUSTOM_MODELS_SECRETS

  belongs_to :organization, required: true, inverse_of: :models_custom_keys

  has_many :custom_models, class_name: "ModelsByok::CustomModel", inverse_of: :custom_key
  destroy_dependents_in_background :custom_models

  has_many :organization_access_rules, class_name: "GitHubModels::OrganizationAccessRule", inverse_of: :custom_key

  validates :name, presence: true, length: { maximum: 60 }, uniqueness: { scope: :organization_id },
    format: {
      with: ::GitHub::KredzClient::Credz::SECRET_KEY_VALID_CHAR_REGEX,
      message: "can only contain letters, numbers, or underscores, and must start with a letter or underscore",
    }

  before_validation :setup_kredz_key, on: :create
  validates :kredz_key, presence: true, length: { maximum: 60 }, uniqueness: { scope: :organization_id }

  validate :deployment_url_only_for_azure_ai

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

  sig { params(total_models: T.nilable(Integer)).returns(ModelsByok::Types::CustomKey) }
  def to_h(total_models: nil)
    {
      id: id,
      name: name,
      provider: provider,
      totalModels: total_models || custom_models.size,
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
    GitHub.logger.error("Failed to create secret for custom key", {
      "exception.type": e.class.name,
      "exception.message": e.message,
      "gh.organization.id": organization_id,
      "gh.actor.id": actor.id,
      "custom_key_name": name,
      "kredz_key": kredz_key,
    })
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

  private

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
  end
end
