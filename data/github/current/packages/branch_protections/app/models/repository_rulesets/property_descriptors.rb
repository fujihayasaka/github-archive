# typed: true
# frozen_string_literal: true

module RepositoryRulesets
  module PropertyDescriptors

    sig { params(property_source: T.any(Organization, Business)).returns(T::Array[PropertyDescriptor]) }
    def self.get_descriptors(property_source)
      definitions_manager = if property_source.is_a?(Business)
        ::CustomProperties::Public.business_definitions_manager(property_source)
      else
        ::CustomProperties::Public.definitions_manager(property_source)
      end

      properties = definitions_manager.get_definitions.map do |definition|
        RepositoryRulesets::CustomPropertyDescriptor.new(definition)
      end
      properties += RepositoryRulesets::SystemProperties::SYSTEM_PROPERTIES

      # Sort the properties array. Properties with source 'system' are placed first,
      # and then properties are ordered alphabetically by their property_name within each source group.
      properties.sort_by { |p| [p.source == "system" ? 0 : 1, p.property_name] }
    end

    sig do
      params(repository: ::Repository, property_names: T::Array[String]).returns(T::Hash[String, T.untyped])
    end
    private_class_method def self.get_custom_effective_values(repository, property_names)
      custom_effective_values = Repositories.domain.custom_properties.repo_properties(
        [repository],
        :effective,
        strip_nils: true
      ).fetch(repository, {}).transform_keys(&:downcase)

      property_names.each_with_object({}) do |property_name, hash|
        effective_property = custom_effective_values[property_name.downcase]
        hash[property_name] = effective_property if effective_property.present?
      end
    end
  end
end
