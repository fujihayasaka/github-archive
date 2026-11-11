# typed: true
# frozen_string_literal: true

class CopilotByok::CustomKey < ApplicationRecord::Domain::Copilot
  include Instrumentation::Model

  self.table_name = "copilot_custom_keys"
  self.ignored_columns = [:deployment_url]

  ENCRYPTION_KEY_NAME = ::Platform::EncryptionKeys::COPILOT_BYOK_SECRETS

  # Keep in sync with `validHostnames` in
  # packages/copilot-byok/providers/microsoft-foundry.ts in github/github-ui
  # and with `validHosts` in pkg/byok/byokprovider/azureai.go in github/copilot-api
  VALID_MSFOUNDRY_HOSTNAMES = [
    "models.ai.azure.com",
    "inference.ml.azure.com",
    "openai.azure.com",
    "services.ai.azure.com",
    "cognitiveservices.azure.com",
    "ai.openai.azure.us",
  ].freeze

  # A colon is not a valid character in base64 encoding, so it's safe to use as a separator for two
  # base64-encoded strings.
  MULTI_PART_ENCRYPTED_SECRET_VALUE_SEPARATOR = ":"

  # Specifies what each index of a 0-based array of a multi-part secret represents, by provider.
  MULTI_PART_ENCRYPTED_SECRET_VALUE_INDICES_BY_PROVIDER = {
    awsbedrock: { access_key: 0, api_key: 1 }, # AWS Bedrock secrets are [access key, secret access key (API key)]
  }.freeze

  belongs_to :organization, inverse_of: :copilot_custom_keys
  belongs_to :business, inverse_of: :copilot_custom_keys

  has_many :custom_models, -> { includes(:capability) }, class_name: "CopilotByok::CustomModel", inverse_of: :custom_key, dependent: :destroy
  has_many :custom_model_capabilities, through: :custom_models, inverse_of: :custom_key, source: :capability
  has_many :custom_model_rules, class_name: "CopilotByok::CustomModelRule", inverse_of: :target
  destroy_dependents_in_background :custom_model_rules

  encrypts :encrypted_secret_value

  serialize :provider_data, coder: CopilotByok::ProviderData::Coder

  enum :provider, {
    openai: 0,
    azureai: 1,
    anthropic: 2,
    googleaistudio: 3,
    xai: 4,
    openaicompatible: 5,
    awsbedrock: 6,
  }

  # Used to temporarily hold the current user, for use in instrumentation:
  sig { returns T.nilable(User) }
  attr_accessor :actor

  before_validation :set_business_for_org
  before_validation :set_kredz_key_so_not_null

  validates :name, presence: true, length: { maximum: 60 }, format: {
    with: ::GitHub::KredzClient::Credz::SECRET_KEY_VALID_CHAR_REGEX,
    message: "can only contain letters, numbers, or underscores, and must start with a letter or underscore",
  }

  before_destroy :verify_no_models

  validates :encrypted_secret_value, presence: true
  validate :encrypted_secret_value_decryptable
  validate :owner_specified
  validate :owner_exists, on: :create
  validate :org_belongs_to_business
  validate :unique_name_per_owner

  after_commit :instrument_creation_event, on: :create
  after_commit :instrument_update_event, on: :update
  after_destroy_commit :instrument_deletion_event

  scope :for_org, ->(org_or_id) { where(organization_id: org_or_id) }
  scope :for_enterprise, ->(biz_or_id) { where(organization_id: nil, business_id: biz_or_id) }
  scope :newest_first, -> { order(created_at: :desc) }

  scope :for_user, ->(user) do
    user = T.let(user, ::User)
    for_org(user.organization_ids)
      .or(for_enterprise(user.business_ids))
  end

  accepts_nested_attributes_for :custom_models

  # Public: Get a hash mapping custom key IDs to a count of how many models are associated with the custom key.
  sig { params(models: T::Array[CopilotByok::CustomModel]).returns(T::Hash[Integer, Integer]) }
  def self.model_counts_by_id(models)
    models.each_with_object(Hash.new(0)) do |model, hash|
      hash[model.custom_key_id] += 1
    end
  end

  sig { returns T.nilable(T.any(Organization, Business)) }
  def owner
    organization || business
  end

  sig { returns T.nilable(Integer) }
  def owner_id
    organization_id || business_id
  end

  sig { returns T::Boolean }
  def organization_owned?
    organization_id.present?
  end

  sig { returns T::Boolean }
  def enterprise_owned?
    !organization_owned?
  end

  # Public: For use in audit log instrumentation, to describe what this record is.
  sig { returns Symbol }
  def event_prefix
    :copilot_custom_key
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
    business = self.business
    payload[business.event_prefix] = business if business
    payload
  end

  # Stable providers are those that have support in admin surfaces, and inference support in CAPI.
  STABLE_PROVIDERS = %i(openai azureai anthropic googleaistudio xai).freeze
  PROVIDER_ROLLOUT_FLAGS = T.let({
    openaicompatible: :copilot_byok_provider_openaicompatible,
    awsbedrock: :copilot_byok_provider_awsbedrock,
  }.freeze, T::Hash[Symbol, Symbol])

  sig { params(entity: T.any(Business, Organization)).returns(T::Array[Symbol]) }
  def self.available_providers_for(entity)
    actors = [entity]
    actors << T.must(entity.business) if entity.is_a?(Organization) && entity.business.present?

    CopilotByok::CustomKey.providers.keys.map(&:to_sym).select do |provider|
      next true if STABLE_PROVIDERS.include?(provider)

      flag = PROVIDER_ROLLOUT_FLAGS[provider]
      next false unless flag

      FeatureFlag.vexi.enabled?(flag, *actors, default: false)
    end
  end

  sig { params(entity: T.any(Business, Organization), provider: Symbol).returns(T::Boolean) }
  def self.valid_provider_for?(entity, provider)
    available_providers_for(entity).include?(provider)
  end

  sig do
    params(total_models: T.nilable(Integer), editable: T.nilable(T::Boolean)).returns(CopilotByok::Types::CustomKey)
  end
  def to_h(total_models: nil, editable: nil)
    owner = self.owner
    {
      id: id,
      name: name,
      provider: provider,
      totalModels: total_models || custom_models.size,
      deploymentUrl: azureai? ? deployment_url : nil, # Only for AzureAI provider
      baseUrl: openaicompatible? && provider_data ? provider_data.base_url : nil, # Only for OpenAI Compatible provider
      editable: editable,
      ownerName: owner&.name || "unknown",
      region: region,
    }
  end

  sig { returns T.nilable(String) }
  def region
    provider_data.try(:region)
  end

  # Public: Get the deployment URL for Azure AI custom keys.
  sig { returns T.nilable(String) }
  def deployment_url
    return nil unless azureai?
    return nil unless provider_data.is_a?(CopilotByok::ProviderData::CustomKey::MicrosoftFoundry)
    provider_data.deployment_url
  end

  sig { params(owner: T.any(Business, Organization)).returns([Integer, String]) }
  def self.encryption_public_key(owner)
    Secrets.github_public_key(owner: owner, key_name: ENCRYPTION_KEY_NAME)
  end

  sig { params(value: String, owner: T.any(Business, Organization)).returns(String) }
  def self.embed_value(value, owner:)
    key_id, _ = encryption_public_key(owner)
    value = Secrets.embed(key_id, Base64.strict_decode64(value))
    Base64.strict_encode64(value)
  end

  sig { params(values: T::Array[String], owner: T.any(Business, Organization)).returns(String) }
  def self.embed_multi_part_value(values, owner:)
    values.map { |value| embed_value(value, owner: owner) }.join(MULTI_PART_ENCRYPTED_SECRET_VALUE_SEPARATOR)
  end

  # Public: Put together an array of the parts that constitute a multi-part secret.
  #
  # part_indices - a mapping that indicates which part of the secret should go where in the array
  # access_key - the access key part of the secret, if applicable
  # api_key - the API key part of the secret, if applicable
  # fallback_parts - fallback values for each part if a new value is not provided for each part
  sig do
    params(
      part_indices: T::Hash[Symbol, Integer],
      access_key: T.nilable(String),
      api_key: T.nilable(String),
      fallback_parts: T.nilable(T::Array[String])
    ).returns(T::Array[String])
  end
  def self.build_parts_for_embedding_multi_part_value(part_indices, access_key: nil, api_key: nil, fallback_parts: nil)
    access_key_index = part_indices[:access_key]
    api_key_index = part_indices[:api_key]
    parts = T.let([], T::Array[String])
    if access_key_index
      access_key ||= fallback_parts[access_key_index] if fallback_parts
      parts[access_key_index] = access_key.presence if access_key
    end
    if api_key_index
      api_key ||= fallback_parts[api_key_index] if fallback_parts
      parts[api_key_index] = api_key.presence if api_key
    end
    parts.compact
  end

  # Public: Does this custom key's provider require more than one secret to use its models?
  sig { returns T::Boolean }
  def multi_part_secret?
    awsbedrock?
  end

  # Public: Returns either a single decrypted secret for accessing this custom key's provider API, or an array of
  # decrypted secrets for a provider who requires more than one secret for authentication.
  sig { returns T.nilable(T.any(String, T::Array[String])) }
  def decrypt_secret
    owner = self.owner
    return unless owner && encrypted_secret_value.present?

    if multi_part_secret?
      self.class.decrypt_multi_part_secret(encrypted_secret_value, owner: owner)
    else
      self.class.decrypt_secret(encrypted_secret_value, owner: owner)
    end
  rescue => e
    GitHub.logger.error("encrypted_secret_value is not decryptable", {
      "exception.type": e.class.name,
      "exception.message": e.message,
      "custom_key_name": name,
      "gh.actor.id": actor&.id,
      "gh.organization.id": organization_id,
      "gh.business.id": business_id,
    }.compact)
    nil
  end

  sig do
    params(
      api_key: T.nilable(String),
      owner: T.any(Business, Organization),
      custom_key: T.nilable(CopilotByok::CustomKey)
    ).returns(T.nilable(String))
  end
  def self.decrypt_api_key(api_key, owner:, custom_key: nil)
    return if custom_key&.multi_part_secret?
    encoded_api_key = if api_key.blank?
      custom_key&.encrypted_secret_value
    else
      embed_value(api_key, owner: owner)
    end
    return if encoded_api_key.nil?
    decrypt_secret(encoded_api_key, owner: owner)
  end

  sig do
    params(
      api_key_parts: T.nilable(T::Array[String]),
      owner: T.any(Business, Organization),
      custom_key: T.nilable(CopilotByok::CustomKey)
    ).returns(T.nilable(T::Array[String]))
  end
  def self.decrypt_multi_part_api_key(api_key_parts, owner:, custom_key: nil)
    return if custom_key && !custom_key.multi_part_secret?
    encoded_api_key_parts = if api_key_parts.nil? || api_key_parts.empty?
      custom_key&.encrypted_secret_value
    else
      embed_multi_part_value(api_key_parts, owner: owner)
    end
    return if encoded_api_key_parts.nil?
    decrypt_multi_part_secret(encoded_api_key_parts, owner: owner)
  end

  sig { params(encrypted_value: String, owner: T.any(Business, Organization)).returns(String) }
  def self.decrypt_secret(encrypted_value, owner:)
    decoded_value = Base64.strict_decode64(encrypted_value)
    earthsmoke_key = DietEarthsmoke::Key.new(ENCRYPTION_KEY_NAME)
    earthsmoke_key.open(decoded_value, scope: owner.next_global_id)
  end

  sig { params(encrypted_value: String, owner: T.any(Business, Organization)).returns(T::Array[String]) }
  def self.decrypt_multi_part_secret(encrypted_value, owner:)
    encrypted_parts = encrypted_value.split(MULTI_PART_ENCRYPTED_SECRET_VALUE_SEPARATOR)
    raise ArgumentError, "Expected multi-part secret" unless encrypted_parts.size > 1
    encrypted_parts.map { |encrypted_part| decrypt_secret(encrypted_part, owner: owner) }
  end

  # Public: This extracting encrypted parts from a multi-part secret without decrypting them. It returns a result
  # that can then be decrypted fully by #decrypt_multi_part_api_key if desired. Will return nil for custom keys that
  # have a single-part secret, or if the owner no longer exists.
  sig { returns T.nilable(T::Array[String]) }
  def encrypted_secret_value_parts
    return unless multi_part_secret? && encrypted_secret_value

    owner = self.owner
    return unless owner

    public_key_id, _ = self.class.encryption_public_key(owner)
    encrypted_secret_value.split(MULTI_PART_ENCRYPTED_SECRET_VALUE_SEPARATOR).map do |encoded_part|
      decoded_part = Base64.strict_decode64(encoded_part)
      unembedded_part = Secrets.unembed(public_key_id, decoded_part)
      Base64.strict_encode64(unembedded_part)
    end
  end

  sig do
    params(fresh_provider_models: T::Array[CopilotByok::Types::SelectorCustomModel])
      .returns(T::Array[CopilotByok::Types::SelectorCustomModel])
  end
  def reconcile_custom_models_with_provider(fresh_provider_models)
    result = T.let([], T::Array[CopilotByok::Types::SelectorCustomModel])
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

  private

  def owner_specified
    if organization_id.nil? && business_id.nil?
      errors.add(:base, "Either an organization or an enterprise must be specified")
    end
  end

  def owner_exists
    if organization_id && organization.nil?
      errors.add(:organization_id, "does not exist")
    elsif business_id && business.nil?
      errors.add(:business_id, "does not exist")
    end
  end

  def set_business_for_org
    return unless organization_id
    self.business_id ||= organization&.business&.id
  end

  def org_belongs_to_business
    return unless organization_id && business_id

    organization = self.organization
    return unless organization

    unless organization.business&.id == business_id
      errors.add(:business_id, "does not own the organization")
    end
  end

  def unique_name_per_owner
    return if name.blank?
    return unless organization_id || business_id

    scope = organization_id ? self.class.for_org(organization_id) : self.class.for_enterprise(business_id)
    scope = scope.where.not(id: id) if persisted?
    if scope.where(name: name).any?
      errors.add(:name, "has already been taken")
    end
  end

  def instrument_creation_event
    prefix, action = Copilot::Events::COPILOT_CUSTOM_KEY_CREATED.split(".", 2)
    # Audit log:
    instrument action, prefix: prefix
  end

  def instrument_update_event
    prefix, action = Copilot::Events::COPILOT_CUSTOM_KEY_UPDATED.split(".", 2)
    extra_payload = { prefix: prefix }
    unless name == name_before_last_save
      extra_payload["old_#{event_prefix}".to_sym] = name_before_last_save
    end

    # Track deployment_url changes for Azure AI keys (read from provider_data)
    if azureai?
      old_deployment_url = if saved_change_to_provider_data?
        old_provider_data = saved_change_to_provider_data&.first
        old_provider_data.is_a?(CopilotByok::ProviderData::CustomKey::MicrosoftFoundry) ? old_provider_data.deployment_url : nil
      else
        deployment_url
      end

      if deployment_url != old_deployment_url
        extra_payload[:old_deployment_url] = old_deployment_url
      end
    end

    # Audit log:
    instrument(action, extra_payload) unless extra_payload.empty?
  end

  def instrument_deletion_event
    prefix, action = Copilot::Events::COPILOT_CUSTOM_KEY_DELETED.split(".", 2)
    # Audit log:
    instrument action, prefix: prefix
  end

  def verify_no_models
    any_custom_models = custom_models.any?
    return unless any_custom_models

    errors.add(:base, "Custom models must be deleted first")
    throw :abort
  end

  def encrypted_secret_value_decryptable
    return if encrypted_secret_value.blank?

    # We store an earthsmoke encrypted value; try to decrypt it to verify it's valid.
    decrypted_value = decrypt_secret
    if decrypted_value.nil?
      # The caller doesnt need to know what specifically about the secret is invalid, just that it is.
      errors.add(:encrypted_secret_value, "is invalid")
    end
  end

  # We are no longer using the kredz_key field but it has a `NOT NULL` constraint in the database, so we have to
  # set it to something to be able to insert new records.
  def set_kredz_key_so_not_null
    self.kredz_key ||= ""
  end
end
