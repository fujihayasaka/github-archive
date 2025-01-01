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

    sig { returns T::Boolean }
    def copilot_custom_models_enabled?
      return false unless GitHub.copilot_enabled?
      return T.must(business).custom_models_enabled? if business.present?
      true
    end
  end
end
