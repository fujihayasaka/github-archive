# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Suggestions
    module Orgs
      class CustomProperty < Base
        extend T::Sig

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

        sig { returns(T.nilable(CustomPropertyDefinition)) }
        memoize def custom_property_definition
          CustomPropertyDefinition
            .for(organization)
            .find_by(property_name: name)
        end

        sig { returns(T::Array[String]) }
        def custom_property_values
          return [] if custom_property_definition.blank?
          definition = T.must(custom_property_definition)

          res =
            if definition.true_false_value_type?
              values = %w[true false] - selected_values
              values = values.select { |v| v.include?(value) } if value.present?
              values = values.take(limit) if limit.present?
              values
            elsif definition.single_select_value_type? || definition.multi_select_value_type?
              values = definition.allowed_values.sort - selected_values
              values = values.select { |v| v.include?(value) } if value.present?
              values = values.take(limit) if limit.present?
              values
            elsif definition.string_value_type?
              values_rel = definition
                .custom_property_values
                .distinct
                .then do |rel|
                  next rel if allowed_repo_ids.nil? # admin

                  rel.where(target_id: allowed_repo_ids) # non-admin
                end
                .where(target_type: "Repository")
                .order(:value)

              values_rel = values_rel.limit(limit) if limit.present?
              values_rel = values_rel.where.not(value: selected_values) if selected_values.present?
              values_rel = values_rel.where("value LIKE ?", "%#{value}%") if value.present?

              values = definition.default_value.present? ? [definition.default_value] : []
              values + values_rel.pluck(:value)
            else
              []
            end

          res.compact.uniq.sort
        end
      end
    end
  end
end
