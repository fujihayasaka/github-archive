# typed: true
# frozen_string_literal: true

module Organization::CopilotByokDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { Organization }

  included do
    T.bind(self, T.class_of(Organization))

    has_many :copilot_custom_keys, class_name: "CopilotByok::CustomKey", inverse_of: :organization
    has_many :copilot_custom_models, class_name: "CopilotByok::CustomModel", inverse_of: :organization,
      source: :custom_models, through: :copilot_custom_keys, disable_joins: true
    has_many :copilot_custom_model_rules, class_name: "CopilotByok::CustomModelRule", inverse_of: :organization

    sig { returns T::Boolean }
    def copilot_custom_models_enabled?
      return false unless GitHub.copilot_enabled?

      return T.must(business).copilot_custom_models_enabled? if business.present?

      true
    end

    # Public: Returns a sorted list of custom models enabled for Copilot Chat in this organization.
    # Includes:
    # - Custom models from the organization's custom keys
    # - Custom models from the business if the organization belongs to one
    sig { returns T::Array[CopilotByok::CustomModel] }
    def enabled_custom_models
      T.bind(self, Organization)
      return [] unless copilot_custom_models_enabled?

      organization_models = copilot_custom_models.includes(:custom_key).enabled_for_copilot_chat

      business_enabled_models = []

      org_business = business
      if org_business.present?
        policy = CopilotByok::CustomModelPolicy.new(business: org_business)
        business_enabled_models = policy.enabled_models_for(self)
      end

      unsorted_result = organization_models + business_enabled_models
      unsorted_result.sort { |a, b| ::CopilotByok::CustomModel.key_and_name_sort(a, b) }
    end
  end
end
