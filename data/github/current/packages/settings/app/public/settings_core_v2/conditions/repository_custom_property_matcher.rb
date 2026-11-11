# typed: strict
# frozen_string_literal: true

module SettingsCoreV2
  module Conditions
    class RepositoryCustomPropertyMatcher < SettingsCoreV2::ConditionMatcher
      ATTRIBUTE = "repository.custom_properties"

      sig { override.returns(String) }
      def attribute
        ATTRIBUTE
      end

      sig { override.params(resource: T.untyped, sub_type: T.nilable(String)).returns(T.nilable(String)) }
      def effective_value(resource, sub_type = nil)
        return nil unless resource.is_a?(Repository)
        return nil unless sub_type.present?
        resource.custom_properties_effective_values[sub_type]
      end

      sig { override.params(parent: T.untyped, operation: IConditionExpression::Operation, value: T.any(String, T::Array[String]), sub_type: T.nilable(String)).returns({ count: Integer, total: Integer }) }
      def count_matches(parent, operation, value, sub_type = nil)
        return { count: 0, total: 0 } unless parent.is_a?(Organization)

        total = parent.repositories.count

        return { count: 0, total: } unless sub_type.present?

        definition = Repositories.domain.custom_properties.get_definition(parent, sub_type)
        return { count: 0, total: } unless definition

        match_count = CustomPropertyValue.where(
          definition_id: definition.id,
          value: value,
        ).count

        count = case operation
        when IConditionExpression::Operation::NE, IConditionExpression::Operation::NIN
          total - match_count
        else
          match_count
        end

        { count:, total: }
      end

      sig { override.params(parent: T.untyped).returns(T.nilable(T::Array[T::Hash[String, T.untyped]])) }
      def metadata(parent)
        return nil unless parent.is_a?(Organization)

        definitions = Repositories.domain.custom_properties.get_definitions(parent)
        definitions.map do |d|
          {
            "name" => d.property_name,
            "description" => d.description,
            "valueType" => d.value_type,
            "allowedValues" => d.allowed_values,
            "required" => d.required,
            "defaultValue" => d.default_value,
          }
        end
      end
    end
  end
end
