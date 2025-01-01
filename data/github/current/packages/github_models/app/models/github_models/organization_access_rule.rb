# typed: true
# frozen_string_literal: true

class GitHubModels::OrganizationAccessRule < ApplicationRecord::Domain::GitHubModels
  include Instrumentation::Model

  belongs_to :organization, required: true, inverse_of: :github_models_access_rules
  belongs_to :catalog_item, class_name: "GitHubModels::CatalogItem", inverse_of: :organization_access_rules,
    primary_key: :key, foreign_key: :catalog_item_key
  belongs_to :publisher, class_name: "GitHubModels::Publisher", foreign_key: "models_publisher_id",
    inverse_of: :organization_access_rules

  before_validation :set_publisher_for_catalog_item

  validates :allow, inclusion: [true, false]
  validate :publisher_exists_if_specified, on: :create
  validate :publisher_matches_catalog_item
  validate :rule_is_unique_per_org
  validate :global_rule_blocks_access

  # Used to temporarily hold the current user, for use in instrumentation:
  sig { returns T.nilable(User) }
  attr_accessor :actor

  after_commit :instrument_creation_event, on: :create
  after_commit :instrument_update_event, on: :update
  after_destroy_commit :instrument_deletion_event

  self.table_name = "models_organization_access_rules"

  scope :allowed, -> { where(allow: true) }
  scope :blocked, -> { where(allow: false) }
  scope :global, -> { where(catalog_item_key: nil, models_publisher_id: nil) }
  scope :targeted, -> { where.not(catalog_item_key: nil).or(where.not(models_publisher_id: nil)) }
  scope :for_org, ->(org_or_id) { where(organization: org_or_id) }

  # Public: Whether this rule denies access to the model or publisher it targets.
  sig { returns T::Boolean }
  def block?
    !allow?
  end

  # Public: Whether this rule is about GitHub Models in its entirety, and not pertaining to a particular
  # publisher or model.
  sig { returns T::Boolean }
  def global?
    catalog_item_key.blank? && models_publisher_id.nil?
  end

  sig { returns T.nilable(T.any(GitHubModels::CatalogItem, GitHubModels::Publisher)) }
  def target
    catalog_item || publisher
  end

  sig { returns String }
  def target_label
    return "GitHub Models access" unless target
    target.is_a?(GitHubModels::CatalogItem) ? "model" : "publisher"
  end

  # Public: Is this rule about allowing or blocking access to a specific model?
  sig { returns T::Boolean }
  def model_specific?
    catalog_item_key.present?
  end

  # Public: Is this rule about allowing or blocking access to all models from a particular publisher?
  sig { returns T::Boolean }
  def publisher_specific?
    !models_publisher_id.nil? && catalog_item_key.blank?
  end

  sig { returns String }
  def to_s
    verb = allow? ? "Allow" : "Block"
    target = self.target
    target_name = if target.is_a?(GitHubModels::CatalogItem)
      target.friendly_name
    elsif target.is_a?(GitHubModels::Publisher)
      target.name
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

  def set_publisher_for_catalog_item
    self.models_publisher_id ||= catalog_item&.github_models_publisher_id
  end

  def publisher_matches_catalog_item
    return unless models_publisher_id

    catalog_item = self.catalog_item
    return unless catalog_item

    unless models_publisher_id == catalog_item.github_models_publisher_id
      errors.add(:catalog_item, "does not match publisher")
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
    duplicate_rules = if catalog_item_key
      duplicate_rules.where(catalog_item_key: catalog_item_key)
    elsif models_publisher_id
      duplicate_rules.where(models_publisher_id: models_publisher_id, catalog_item_key: nil)
    else
      duplicate_rules.global
    end

    if duplicate_rules.exists?
      prefix = global? ? "" : "this "
      errors.add(:organization, "already has a rule for #{prefix}#{target_label}")
    end
  end

  def global_rule_blocks_access
    if allow? && models_publisher_id.nil? && catalog_item_key.blank?
      errors.add(:allow, "must be false for a rule that does not target a specific publisher or model")
    end
  end
end
