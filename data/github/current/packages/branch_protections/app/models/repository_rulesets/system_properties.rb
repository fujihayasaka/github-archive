# typed: true
# frozen_string_literal: true

module RepositoryRulesets
  module SystemProperties
    PropertyParam = T.type_alias { { "name" => String, "property_values" => T::Array[String] } }

    SYSTEM_PROPERTIES = T.let([
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
        validator: ->(value, _context) {
          next false if value.blank?

          deparameterized = value.split("-").join(" ")
          (Linguist::Language.find_by_name(deparameterized) ||
            Linguist::Language.find_by_name(value) ||
            Linguist::Language.find_by_alias(value)).present?
        }
      ),
      SystemPropertyDescriptor.new(
        property_name: "name",
        value_type: "string",
        value_accessor: ->(repository) { repository.name },
        icon: "repo",
        display_name: "Name",
      )
    ].freeze, T::Array[SystemPropertyDescriptor])
    private_constant :SYSTEM_PROPERTIES

    REPOSITORY_SYSTEM_PROPERTY_ICONS = T.let({
      "deployable" => "package",
      "deployed" => "cloud",
      "runtime-risk" => "shield",
    }.freeze, T::Hash[String, String])
    private_constant :REPOSITORY_SYSTEM_PROPERTY_ICONS

    sig { params(property_source: T.nilable(T.any(Organization, Business))).returns(T::Array[PropertyDescriptor]) }
    def self.get_descriptors(property_source)
      # remove property_source when shipping custom_properties_system_properties_runtime_risk
      system_properties = SYSTEM_PROPERTIES.dup + repository_system_property_descriptors.dup
      unless property_source.present? && Repositories.domain.custom_properties.runtime_risk_system_property_enabled?(property_source)
        system_properties = system_properties.reject { |d| d.property_name == "runtime-risk" }
      end
      system_properties
    end

    sig do
      params(repository: Repositories::IRepository).returns(T::Hash[String, CustomPropertiesCore::PropertyValue])
    end
    def self.get_values(repository)
      values_hash = SYSTEM_PROPERTIES.dup.each_with_object({}) do |system_property, hash|
        hash[system_property.property_name] = system_property.value(T.cast(repository, ::Repository)) if system_property
      end

      if repository.owner.is_a?(Organization)
        # Repository domain system properties are only available for org owned repos.
        # We can batch fetch the repository system properties and populate the values hash here
        # rather than calling .value on each descriptor in the loop above.
        values_hash.merge!(Repositories.domain.custom_properties.repo_system_properties([repository]).fetch(repository, {}))
      end

      values_hash.compact
    end

    sig { returns(T::Array[SystemPropertyDescriptor]) }
    private_class_method def self.repository_system_property_descriptors
      @repository_system_property_descriptors ||= T.let(
        Repositories.domain.custom_properties.system_property_definitions.map do |definition|
          SystemPropertyDescriptor.new(
            property_name: definition.property_name,
            value_type: definition.value_type,
            value_accessor: ->(_repository) { nil }, # These will get batch loaded in get_values
            icon: repository_system_property_icon(definition.property_name),
            display_name: definition.property_name.titleize,
            allowed_values: definition.allowed_values,
          )
        end,
        T.nilable(T::Array[SystemPropertyDescriptor])
      ).freeze
    end

    sig { params(property_name: String).returns(String) }
    private_class_method def self.repository_system_property_icon(property_name)
      REPOSITORY_SYSTEM_PROPERTY_ICONS.fetch(property_name) do
        raise ArgumentError, "No icon defined for repository system property '#{property_name}'"
      end
    end
  end
end
