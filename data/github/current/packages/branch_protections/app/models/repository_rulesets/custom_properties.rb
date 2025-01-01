# typed: true
# frozen_string_literal: true

module RepositoryRulesets
  module CustomProperties
    extend T::Sig

    SYSTEM_PROPERTIES = [
      SystemPropertyDescriptor.new(
        property_name: "fork",
        value_type: "true_false",
        value_accessor: ->(repository) { repository.fork?.to_s },
        icon: "repo-forked",
        display_name: "Fork"
      ),
      SystemPropertyDescriptor.new(
        property_name: "visibility",
        value_type: "single_select",
        allowed_values_accessor: -> (ruleset_target) { ruleset_target == "push" ? %w[private internal] : %w[public private internal] },
        value_accessor: ->(repository) { repository.visibility },
        icon: "eye",
        display_name: "Visibility"
      ),
      SystemPropertyDescriptor.new(
        property_name: "language",
        value_type: "single_select",
        value_accessor: ->(repository) { repository.primary_language&.name },
        icon: "code",
        display_name: "Language",
        validator: ->(value, _context) { Linguist::Language[value.downcase.gsub(/\s/, "-")].send(:present?) }
      )
    ].freeze

    sig { params(property_source: T.any(Organization, Business)).returns(T::Array[PropertyDescriptor]) }
    def self.get_property_descriptors(property_source)
      definitions_manager = ::CustomProperties::Public.definitions_manager(property_source)
      properties = definitions_manager.get_definitions.map do |definition|
        RepositoryRulesets::CustomPropertyDescriptor.new(definition)
      end
      properties += SYSTEM_PROPERTIES

      # Sort the properties array. Properties with source 'system' are placed first,
      # and then properties are ordered alphabetically by their property_name within each source group.
      properties.sort_by { |p| [p.source == "system" ? 0 : 1, p.property_name] }
    end

    sig do
      params(repository: ::Repository, source: String, property_names: T::Array[String]).returns(T::Hash[String, T.untyped])
    end
    def self.get_property_values(repository, source, property_names)
      raise ArgumentError, 'Invalid source. Expected "system" or "custom"' unless %w[system custom].include?(source)
      return {} if property_names.empty?

      if source == "system"
        get_system_values(repository, property_names)
      else
        get_custom_effective_values(repository, property_names)
      end
    end

    sig do
      params(repository: ::Repository, property_names: T::Array[String]).returns(T::Hash[String, T.untyped])
    end
    private_class_method def self.get_custom_effective_values(repository, property_names)
      custom_effective_values = ::CustomProperties::Public.repo_properties(
        [repository],
        :effective,
        strip_nils: true
      ).fetch(repository, {}).transform_keys(&:downcase)

      property_names.each_with_object({}) do |property_name, hash|
        effective_property = custom_effective_values[property_name.downcase]
        hash[property_name] = effective_property if effective_property.present?
      end
    end

    sig do
      params(repository: ::Repository, property_names: T::Array[String]).returns(T::Hash[String, ::CustomProperties::PropertyValue])
    end
    private_class_method def self.get_system_values(repository, property_names)
      system_properties = SYSTEM_PROPERTIES.dup

      property_names.each_with_object({}) do |property_name, hash|
        system_property = system_properties.find { |i| i.property_name == property_name }
        hash[property_name] = system_property.value(repository) if system_property
      end
    end
  end
end
