# typed: true
# frozen_string_literal: true

module Organization::ModelsByokDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { Organization }

  included do
    T.bind(self, T.class_of(Organization))

    has_many :models_custom_keys, class_name: "ModelsByok::CustomKey", inverse_of: :organization
    has_many :custom_models, class_name: "ModelsByok::CustomModel", inverse_of: :organization,
      through: :models_custom_keys, disable_joins: true
  end
end
