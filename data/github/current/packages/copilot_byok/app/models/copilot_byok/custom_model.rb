# typed: true
# frozen_string_literal: true

class CopilotByok::CustomModel < ApplicationRecord::Domain::Copilot
  include Instrumentation::Model

  self.table_name = "copilot_custom_models"

  REGISTRY = "custom"
  MAX_SLUG_LENGTH = 80

  belongs_to :custom_key, class_name: "CopilotByok::CustomKey", inverse_of: :custom_models, required: true

  has_one :organization, through: :custom_key, inverse_of: :copilot_custom_models, disable_joins: true
  has_one :business, through: :custom_key, inverse_of: :copilot_custom_models, disable_joins: true
  has_one :capability, class_name: "CopilotByok::CustomModelCapability", inverse_of: :custom_model
  accepts_nested_attributes_for :capability
  has_many :rules, class_name: "CopilotByok::CustomModelRule", inverse_of: :target
  destroy_dependents_in_background :rules

  before_validation :set_name_from_slug

  validates :name, presence: true, length: { maximum: 60 }, uniqueness: { scope: :custom_key_id }
  validates :slug, presence: true, uniqueness: { scope: :custom_key_id }
  validates :slug, unless: :azureai?, length: { maximum: MAX_SLUG_LENGTH }
  validates :slug, if: :azureai?, length: { minimum: 2, maximum: 64 },
    format: {
      with: /\A[a-zA-Z0-9._-]+\z/,
      message: "must be alphanumeric, can include underscores, hyphens, and periods",
    }

  serialize :provider_data, coder: CopilotByok::ProviderData::Coder

  after_commit :instrument_creation_event, on: :create
  after_commit :instrument_update_event, on: :update
  after_destroy_commit :instrument_deletion_event

  scope :alphabetical, -> { order(:name) }
  scope :for_org, ->(org_or_id) { joins(:custom_key).merge(CopilotByok::CustomKey.for_org(org_or_id)) }
  scope :for_enterprise, ->(biz_or_id) { joins(:custom_key).merge(CopilotByok::CustomKey.for_enterprise(biz_or_id)) }
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
    :copilot_custom_model
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
    # Load `organization` relation since it'll be used in audit log events:
    GitHub::PrefillAssociations.prefill_associations(self, :organization)
    GitHub::PrefillAssociations.prefill_associations(self, :business)
    organization = self.organization
    payload[organization.event_prefix] = organization if organization
    business = self.business
    payload[business.event_prefix] = business if business
    payload
  end

  # Public: Load many custom models based on ID, filtered to those belonging to the specified organization.
  sig { params(ids: T::Array[Integer], org: T.any(Organization, Integer)).returns(T::Array[CopilotByok::CustomModel]) }
  def self.find_many(ids, org:)
    for_org(org).where(id: ids).alphabetical.to_a
  end

  sig { returns T.nilable(String) }
  def custom_key_name
    custom_key&.name
  end

  sig { params(custom_model_a: CopilotByok::CustomModel, custom_model_b: CopilotByok::CustomModel).returns(Integer) }
  def self.key_and_name_sort(custom_model_a, custom_model_b)
    if custom_model_a.custom_key_id == custom_model_b.custom_key_id
      custom_model_a.name.downcase <=> custom_model_b.name.downcase
    else
      GitHub::PrefillAssociations.prefill_associations([custom_model_a, custom_model_b], :custom_key)
      custom_model_a.custom_key_name&.downcase <=> custom_model_b.custom_key_name&.downcase
    end
  end

  sig { returns T.nilable(T.any(Organization, Business)) }
  def owner
    organization || business
  end

  sig { returns T::Boolean }
  def organization_owned?
    if association(:custom_key).loaded? && custom_key
      T.must(custom_key).organization_owned?
    else
      organization.present?
    end
  end

  sig { returns T::Boolean }
  def enterprise_owned?
    !organization_owned?
  end

  sig { params(user: T.nilable(User)).returns(T::Boolean) }
  def readable_by?(user)
    return false unless user

    org_or_biz = self.owner
    return false unless org_or_biz

    org_or_biz.member?(user)
  end

  sig { params(editable: T.nilable(T::Boolean)).returns(CopilotByok::Types::CustomModel) }
  def to_h(editable: nil)
    {
      id: id,
      name: logical_name,
      slug: slug,
      customKeyId: custom_key_id,
      editable: editable,
      enabled: copilot_chat_enabled?,
      toolCalling: capability&.tool_calling || false,
      vision: capability&.vision || false,
      thinking: capability&.thinking || false,
      streaming: capability&.streaming || false,
      maxInputTokens: capability&.max_input_tokens,
      maxOutputTokens: capability&.max_output_tokens,
      maxContextWindow: capability&.max_context_window,
      endpointType: capability&.endpoint_type || "chat_completions",
    }
  end

  sig { returns T.nilable(T::Hash[Symbol, T.untyped]) }
  def to_twirp_user_detail
    custom_key = self.custom_key
    owner = self.owner

    return unless custom_key && owner

    capability = self.capability
    result = {
      owner: twirp_owner_details,
      owner_id: owner.next_global_id,
      provider: custom_key.provider,
      display_name: name,
      model_id: slug,
      key: { id: custom_key.id.to_s, name: custom_key.name },
    }

    result = result.merge(capability.to_twirp_user_detail) if capability
    if custom_key.azureai?
      deployment_url = custom_key.deployment_url
      result[:azure_ai] = { deployment_url: deployment_url } if deployment_url.present?
    end

    result
  end

  # Public: Override ApplicationRecord::Base#reset_memoized_attributes to make sure that we clear memoization
  # variables on reload.
  sig { void }
  def reset_memoized_attributes
    remove_instance_variable(:@capabilities) if defined?(@capabilities)
  end

  sig { returns(CopilotByok::Types::SelectorCustomModel) }
  def to_selector_model
    CopilotByok::Types::SelectorCustomModel.new(
      id: id,
      slug: slug,
      name: logical_name,
      selected: true,
      # CreatedAt is the created date of the providers' model, not the timestamp of our CustomModel entity.
      # TODO: We should properly track that value somewhere
      createdAt: nil,
    )
  end

  private

  sig { returns T::Hash[Symbol, T::Hash[Symbol, T.untyped]] }
  def twirp_owner_details
    owner = self.owner
    return {} if owner.nil?

    if owner.is_a?(Business)
      {
        enterprise: {
          id: owner.id,
          name: owner.display_login,
        }
      }
    else
      {
        organization: {
          id: owner.id,
          name: owner.display_login,
        }
      }
    end
  end

  delegate :actor, to: :custom_key, allow_nil: true

  def instrument_creation_event
    prefix, action = Copilot::Events::COPILOT_CUSTOM_MODEL_CREATED.split(".", 2)
    # Audit log:
    instrument action, prefix: prefix
  end

  def instrument_update_event
    prefix, action = Copilot::Events::COPILOT_CUSTOM_MODEL_UPDATED.split(".", 2)
    extra_payload = { prefix: prefix }
    unless name == name_before_last_save
      extra_payload["old_#{event_prefix}".to_sym] = name_before_last_save
    end
    unless copilot_chat_enabled == copilot_chat_enabled_before_last_save
      extra_payload[:old_copilot_chat_enabled] = copilot_chat_enabled_before_last_save
    end

    # Audit log:
    instrument action, extra_payload
  end

  def instrument_deletion_event
    prefix, action = Copilot::Events::COPILOT_CUSTOM_MODEL_DELETED.split(".", 2)
    # Audit log:
    instrument action, prefix: prefix
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
