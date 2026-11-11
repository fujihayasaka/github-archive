# typed: true
# frozen_string_literal: true

module RepositoryRulesets
  module PropertyDescriptors
    sig { params(property_source: T.any(Organization, Business)).returns(T::Array[PropertyDescriptor]) }
    def self.get_descriptors(property_source)
      definitions = Repositories.domain.custom_properties.get_definitions(property_source)

      properties = definitions.map do |definition|
        RepositoryRulesets::CustomPropertyDescriptor.new(definition)
      end

      # remove property_source when shipping custom_properties_system_properties_runtime_risk
      properties += RepositoryRulesets::SystemProperties.get_descriptors(property_source)

      # Sort the properties array. Properties with source 'system' are placed first,
      # and then properties are ordered alphabetically by their property_name within each source group.
      properties.sort_by { |p| [p.source == "system" ? 0 : 1, p.property_name] }
    end

    sig { params(property_business_source: Business).returns(T::Array[PropertyDescriptor]) }
    def self.get_org_descriptors(property_business_source)
      definitions = Orgs.domain.custom_properties.get_definitions(property_business_source)
      definitions.map { |definition| RepositoryRulesets::CustomPropertyDescriptor.new(definition) }
    end
  end
end
