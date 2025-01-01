# typed: true
# frozen_string_literal: true

class ModelsByok::CustomModel < ApplicationRecord::Domain::GitHubModels
  belongs_to :custom_key, class_name: "ModelsByok::CustomKey", inverse_of: :custom_models, required: true

  has_one :organization, through: :custom_key, inverse_of: :custom_models, disable_joins: true

  before_validation :set_name_from_slug

  validates :name, presence: true, length: { maximum: 60 }, uniqueness: { scope: :custom_key_id }
  validates :slug, presence: true, length: { maximum: 80 }, uniqueness: { scope: :custom_key_id }

  has_many :organization_access_rules, class_name: "GitHubModels::OrganizationAccessRule", inverse_of: :custom_model

  scope :alphabetical, -> { order(:name) }
  scope :for_org, ->(org_or_id) { joins(:custom_key).merge(ModelsByok::CustomKey.for_org(org_or_id)) }
  scope :newest_first, -> { order(created_at: :desc) }

  # Public: For use in audit log instrumentation, to describe what this record is.
  sig { returns Symbol }
  def event_prefix
    :custom_model
  end

  # Public: For use in audit log instrumentation, to give basic information about this record when it's included
  # in another record's audit log event.
  def event_context(prefix: event_prefix)
    { prefix => name, "#{prefix}_slug".to_sym => slug, "#{prefix}_id".to_sym => id }
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

  sig { params(user: T.nilable(User)).returns(T::Boolean) }
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
      name: name.eql?(slug) ? nil : name,
      slug: slug,
      customKeyId: custom_key_id,
      enabled: {
        copilot: copilot_chat_enabled,
        models: false, # TODO: Wire up access settings
      },
    }
  end

  private

  def set_name_from_slug
    return if name.present?
    self.name = slug
  end
end
