# typed: true
# frozen_string_literal: true

module Orgs
  module SecurityCenter
    module CustomPropertiesHelper
      extend T::Sig

      sig { params(organization: Organization).returns(T::Array[T::Hash[Symbol, String]]) }
      def get_custom_properties_for_frontend(organization)
        ::CustomPropertyDefinition
          .for(organization)
          .order(:property_name)
          .limit(::CustomProperties::Public::DEFINITION_LIMIT)
          .map do |definition|
            {
              name: definition.property_name,
              type: definition.value_type
            }
          end
      end
    end
  end
end
