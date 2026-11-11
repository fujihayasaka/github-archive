# typed: true
# frozen_string_literal: true

# Public: Rules set by an enterprise for which custom Copilot models can be used by their organizations.
class CopilotByok::CustomModelRule < ApplicationRecord::Domain::Copilot
  self.table_name = "copilot_custom_model_rules"

  attribute :status, ActiveRecord::Type::Integer.new

  belongs_to :business, required: true, inverse_of: :copilot_custom_model_rules
  belongs_to :organization, inverse_of: :copilot_custom_model_rules
  belongs_to :target, polymorphic: true, required: true

  validates :status, presence: true
  validates :target_id, uniqueness: { scope: [:business_id, :organization_id, :target_type] }
  validates :target_type, inclusion: { in: ["CopilotByok::CustomKey", "CopilotByok::CustomModel"] }
  validate :org_belongs_to_business
  validate :target_belongs_to_business

  enum :status, { disabled: 0, enabled: 1 }

  scope :for_org, ->(org_or_id) { where(organization_id: org_or_id) }
  scope :global, -> { where(organization_id: nil) }
  scope :org_specific, -> { where.not(organization_id: nil) }
  scope :for_enterprise, ->(biz_or_id) { where(business_id: biz_or_id) }
  scope :for_custom_model, ->(model_or_id) { where(target_id: model_or_id, target_type: "CopilotByok::CustomModel") }
  scope :for_custom_key, ->(key_or_id) { where(target_id: key_or_id, target_type: "CopilotByok::CustomKey") }

  # Public: Does this policy apply to all the enterprise's organizations, both those it has right now and any new
  # orgs it may get in the future?
  sig { returns T::Boolean }
  def global?
    organization_id.nil?
  end

  # Public: Check if this rule affects the given organization.
  sig { params(org: Organization).returns(T::Boolean) }
  def applies_to_org?(org)
    # If the rule doesn't apply to all the orgs in the enterprise, then it only applies to the given org if it
    # targets that org specifically:
    return organization_id == org.id unless global?

    org_biz_id = if org.association(:business_membership).loaded?
      org.business_membership&.business_id
    else
      org.business&.id
    end
    business_id.present? && org_biz_id == business_id
  end

  # Public: Does this policy apply to a particular custom model?
  sig { returns T::Boolean }
  def custom_model_specific?
    target_type == CopilotByok::CustomModel.name
  end

  # Public: Does this policy apply to all the custom models provided by a particular custom key?
  sig { returns T::Boolean }
  def custom_key_specific?
    target_type == CopilotByok::CustomKey.name
  end

  sig { returns T.nilable(CopilotByok::CustomModel) }
  def custom_model
    custom_model_specific? ? target : nil
  end

  sig { returns T.nilable(CopilotByok::CustomKey) }
  def custom_key
    custom_key_specific? ? target : nil
  end

  sig { returns T.nilable(Integer) }
  def custom_model_id
    custom_model_specific? ? target_id : nil
  end

  sig { returns T.nilable(Integer) }
  def custom_key_id
    custom_key_specific? ? target_id : nil
  end

  private

  def org_belongs_to_business
    return unless organization_id && business_id

    organization = self.organization
    if organization && organization.business&.id != business_id
      errors.add(:organization, "does not belong to enterprise")
    end
  end

  def target_belongs_to_business
    return unless business_id && target_id && target_type

    target = self.target
    return unless target

    unless target.business&.id == business_id
      errors.add(:target, "does not belong to enterprise")
    end

    if target.organization_owned?
      errors.add(:target, "must be owned by enterprise but is owned by organization")
    end
  end
end
