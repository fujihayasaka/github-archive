# typed: strict
# frozen_string_literal: true

module Organization::CustomPropertiesDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  include ::CustomPropertiesCore::IPropertyTarget

  requires_ancestor { Organization }

  included do
    T.bind(self, T.class_of(Organization))

    sig { override.returns(T.nilable(Integer)) }
    def properties_target_id
      id
    end

    sig { override.returns(T.nilable(Integer)) }
    def properties_org_source_id
      nil
    end

    sig { override.returns(T.nilable(Integer)) }
    def properties_business_source_id
      business&.id
    end
  end
end
