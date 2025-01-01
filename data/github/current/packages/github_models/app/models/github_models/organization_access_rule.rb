# typed: true
# frozen_string_literal: true

class GitHubModels::OrganizationAccessRule < ApplicationRecord::Domain::GitHubModels
  include Instrumentation::Model

  belongs_to :organization, required: true, inverse_of: :github_models_access_rules
  belongs_to :model, class_name: "GitHubModels::Model", inverse_of: :organization_access_rules,
    primary_key: :slug, foreign_key: :catalog_item_key
  belongs_to :custom_key, class_name: "ModelsByok::CustomKey", inverse_of: :organization_access_rules
  belongs_to :custom_model, class_name: "ModelsByok::CustomModel", inverse_of: :organization_access_rules
  belongs_to :publisher, class_name: "GitHubModels::Publisher", foreign_key: "models_publisher_id",
    inverse_of: :organization_access_rules

  before_validation :set_publisher_for_model
  before_validation :set_custom_key_for_custom_model

  validates :allow, inclusion: [true, false]
  validate :publisher_exists_if_specified, on: :create
  validate :publisher_matches_model
  validate :custom_key_matches_custom_model
  validate :rule_is_unique_per_org
  validate :global_rule_blocks_access
  validate :default_and_custom_models_are_mutually_exclusive
  validate :custom_key_matches_organization

  # Used to temporarily hold the current user, for use in instrumentation:
  sig { returns T.nilable(User) }
  attr_accessor :actor

  after_commit :instrument_creation_event, on: :create
  after_commit :instrument_update_event, on: :update
  after_destroy_commit :instrument_deletion_event

  self.table_name = "models_organization_access_rules"

  scope :allowed, -> { where(allow: true) }
  scope :blocked, -> { where(allow: false) }
  scope :global, -> do
    where(catalog_item_key: nil, models_publisher_id: nil, custom_model_id: nil, custom_key_id: nil)
  end
  scope :targeted, -> do
    where.not(catalog_item_key: nil) # default model-specific rules
      .or(where.not(models_publisher_id: nil)) # publisher-specific rules
      .or(where.not(custom_model_id: nil)) # custom model-specific rules
      .or(where.not(custom_key_id: nil)) # custom key-specific rules
  end
  scope :for_org, ->(org_or_id) { where(organization: org_or_id) }

  # Public: Returns the identifier of the default model this rule applies to, if any.
  sig { returns T.nilable(String) }
  def model_slug
    catalog_item_key
  end

  # Public: Set the identifier of the default model this rule applies to.
  sig { params(value: T.nilable(String)).void }
  def model_slug=(value)
    self.catalog_item_key = value
  end

  # Public: Returns the name of the publisher of the default model this rule applies to, if any.
  sig { returns T.nilable(String) }
  def publisher_name
    publisher&.name
  end

  # Public: Returns the URL to view details about the default model this rule applies to, if any.
  sig { returns T.nilable(String) }
  def model_details_path
    model&.details_path
  end

  # Public: Whether this rule denies access to the model or publisher it targets.
  sig { returns T::Boolean }
  def block?
    !allow?
  end

  # Public: Whether this rule is about GitHub Models in its entirety, and not pertaining to a particular
  # publisher or model.
  sig { returns T::Boolean }
  def global?
    model_slug.blank? && models_publisher_id.nil? && custom_model_id.nil? && custom_key_id.nil?
  end

  sig do
    returns(T.nilable(T.any(
      GitHubModels::IModel,
      ModelsByok::CustomModel,
      GitHubModels::Publisher,
      ModelsByok::CustomKey
    )))
  end
  def target
    model || custom_model || publisher || custom_key
  end

  sig { returns String }
  def target_label
    if custom_model_specific?
      "custom model"
    elsif default_model_specific?
      "model"
    elsif custom_key_specific?
      "custom key"
    elsif publisher_specific?
      "publisher"
    else
      "all models except those specified"
    end
  end

  # Public: Is this rule about allowing or blocking access to a specific default model?
  sig { returns T::Boolean }
  def default_model_specific?
    model_slug.present?
  end

  # Public: Is this rule about allowing or blocking access to a specific custom model?
  sig { returns T::Boolean }
  def custom_model_specific?
    !custom_model_id.nil?
  end

  # Public: Is this rule about allowing or blocking access to all models from a particular publisher?
  sig { returns T::Boolean }
  def publisher_specific?
    !models_publisher_id.nil? && model_slug.blank?
  end

  # Public: Is this rule about allowing or blocking access to all custom models coming from a particular custom key?
  sig { returns T::Boolean }
  def custom_key_specific?
    !custom_key_id.nil? && custom_model_id.nil?
  end

  sig { params(model: T.any(GitHubModels::IModel, ModelsByok::CustomModel)).returns(T::Boolean) }
  def for_model?(model)
    if model.respond_to?(:custom_key_id) # custom model
      custom_model_id == T.unsafe(model).id && custom_key_id == T.unsafe(model).custom_key_id
    else # default model
      model_slug == model.slug && models_publisher_id == T.unsafe(model).models_publisher_id
    end
  end

  sig { returns String }
  def to_s
    verb = allow? ? "Allow" : "Block"
    target = self.target
    target_name = if target.respond_to?(:friendly_name)
      T.unsafe(target).friendly_name
    elsif target.respond_to?(:name)
      T.unsafe(target).name
    end
    [verb, target_label, target_name].compact.join(" ")
  end

  # Public: For use in audit log instrumentation, to describe what this record is.
  def event_prefix
    :github_models_organization_access_rule
  end

  def event_context(prefix: event_prefix)
    { prefix => to_s, "#{prefix}_id".to_sym => id }
  end

  def event_payload
    payload = {
      event_prefix => self,
      :allow => allow?,
      :actor => actor,
    }

    organization = self.organization
    payload[organization.event_prefix] = organization if organization

    target = self.target
    payload[target.event_prefix] = target if target

    payload
  end

  private

  def instrument_creation_event
    # Audit log:
    instrument :create
  end

  def instrument_update_event
    # Audit log:
    instrument :update, old_allow: allow_before_last_save
  end

  def instrument_deletion_event
    # Audit log:
    instrument :destroy
  end

  def set_publisher_for_model
    self.models_publisher_id ||= model&.models_publisher_id
  end

  def set_custom_key_for_custom_model
    self.custom_key_id ||= custom_model&.custom_key_id
  end

  def publisher_matches_model
    return unless models_publisher_id

    model = self.model
    return unless model

    unless models_publisher_id == model.models_publisher_id
      errors.add(:model, "does not match publisher")
    end
  end

  def custom_key_matches_custom_model
    return unless custom_key_id

    custom_model = self.custom_model
    return unless custom_model

    unless custom_key_id == custom_model.custom_key_id
      errors.add(:custom_model, "does not match custom key")
    end
  end

  def publisher_exists_if_specified
    return if association(:publisher).loaded? && !publisher.nil?
    if models_publisher_id && !GitHubModels::Publisher.exists?(models_publisher_id)
      errors.add(:models_publisher_id, "is invalid")
    end
  end

  def rule_is_unique_per_org
    return unless organization_id

    duplicate_rules = self.class.for_org(organization_id)
    duplicate_rules = duplicate_rules.where.not(id: id) if persisted?
    duplicate_rules = if model_slug
      duplicate_rules.where(catalog_item_key: model_slug)
    elsif models_publisher_id
      duplicate_rules.where(models_publisher_id: models_publisher_id, catalog_item_key: nil)
    elsif custom_model_id
      duplicate_rules.where(custom_model_id: custom_model_id)
    elsif custom_key_id
      duplicate_rules.where(custom_key_id: custom_key_id, custom_model_id: nil)
    else
      duplicate_rules.global
    end

    if duplicate_rules.exists?
      message = if global? && block?
        "is already using an allowlist"
      elsif !global?
        "already has a rule for this #{target_label}"
      end
      errors.add(:organization, message) if message
    end
  end

  def global_rule_blocks_access
    if allow? && models_publisher_id.nil? && model_slug.blank? && custom_model_id.nil? && custom_key_id.nil?
      errors.add(:allow, "must be false for a rule that does not target a specific publisher or model")
    end
  end

  def default_and_custom_models_are_mutually_exclusive
    return if custom_model_id.nil? && custom_key_id.nil?

    target_label = custom_model_id ? "custom model" : "custom key"
    if model_slug.present?
      errors.add(:model_slug, "must be blank for a rule that targets a #{target_label}")
    elsif models_publisher_id.present?
      errors.add(:models_publisher_id, "must be blank for a rule that targets a #{target_label}")
    end
  end

  def custom_key_matches_organization
    return unless custom_key_id && organization_id

    unless custom_key&.organization_id == organization_id
      errors.add(:custom_key_id, "must belong to the same organization as the access rule")
    end
  end
end
