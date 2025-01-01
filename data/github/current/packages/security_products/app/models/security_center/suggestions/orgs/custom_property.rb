# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Suggestions
    module Orgs
      class CustomProperty < Base

        sig { returns(T.nilable(T::Array[Integer])) }; attr_reader :allowed_repo_ids
        sig { returns(::Organization) }; attr_reader :organization
        sig { returns(String) }; attr_reader :name

        sig { params(allowed_repo_ids: T.nilable(T::Array[Integer]), organization: ::Organization, name: String, kwargs: T.untyped).void }
        def initialize(allowed_repo_ids:, organization:, name:, **kwargs)
          super(**T.unsafe(kwargs))
          @allowed_repo_ids = allowed_repo_ids
          @organization = organization
          @name = name
        end

        sig { override.returns(T::Array[Suggestion]) }
        memoize def suggestions
          return [] if allowed_repo_ids&.empty?
          return [] if name.blank?

          custom_property_values
            .map { |v| Suggestion.new(value: v) }
        end

        private

        sig { returns(T.nilable(CustomProperties::IPropertyDefinition)) }
        memoize def custom_property_definition
          Repositories.domain.custom_properties.get_definition(organization, name)
        end

        sig { returns(T::Array[String]) }
        def custom_property_values
          return [] if custom_property_definition.nil?
          definition = T.must(custom_property_definition)

          if definition.true_false_value_type?
            values = %w[true false] - selected_values
            values = values.select { |v| v.include?(value) } if value.present?
            values = values.take(limit) if limit.present?
            values.compact.uniq.sort
          elsif definition.single_select_value_type? || definition.multi_select_value_type?
            values = Array(definition.allowed_values).sort - selected_values

            has_exact_match = T.let(false, T::Boolean)
            if value.present?
              values = values.select do |v|
                if v == value
                  has_exact_match = true
                  next false
                end
                v.include?(value)
              end
            end

            if has_exact_match
              values = values.take(limit - 1) if limit.present?
              values.compact.uniq.sort.prepend(value)
            else
              values = values.take(limit) if limit.present?
              values.compact.uniq.sort
            end
          elsif definition.string_value_type?
            # We cannot set hard limit, because we don't know if the result will intersect with the selection.
            # But we can use selected items array size to approximate minimal required result array size.
            values_limit = limit + selected_values.size if limit.present?
            values = Repositories.domain.custom_properties.search_property_values(organization, definition.property_name, value, limit: values_limit)
            values = values - selected_values if selected_values.present?

            if definition.default_value.present?
              values = values.concat(Array(definition.default_value))
              values = values.sort
            end

            values = values.take(limit) if limit.present?
            values
          else
            []
          end
        end
      end
    end
  end
end
