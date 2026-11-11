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

    # converge into above array when :custom_properties_system_properties FF is shipped
    DEPLOYMENT_SYSTEM_PROPERTIES = T.let([
      SystemPropertyDescriptor.new(
        property_name: "deployable",
        value_type: "true_false",
        value_accessor: ->(repository) { Array(get_repository_system_property(repository, "deployable")).first },
        icon: "package",
        display_name: "Deployable"
      ),
      SystemPropertyDescriptor.new(
        property_name: "deployed",
        value_type: "true_false",
        value_accessor: ->(repository) { Array(get_repository_system_property(repository, "deployed")).first },
        icon: "cloud",
        display_name: "Deployed"
      )
    ].freeze, T::Array[SystemPropertyDescriptor])

    sig do
      params(repository: Repositories::IRepository).returns(T::Hash[String, String])
    end
    def self.get_values(repository)
      if repository.owner.is_a?(Organization) && Repositories.domain.custom_properties.system_properties_enabled?(T.cast(repository.owner, Organization))
        system_properties = SYSTEM_PROPERTIES.dup + DEPLOYMENT_SYSTEM_PROPERTIES.dup

        values_hash = system_properties.each_with_object({}) do |system_property, hash|
          hash[system_property.property_name] = system_property.value(T.cast(repository, ::Repository)) if system_property
        end

        values_hash.compact
      else
        system_properties = SYSTEM_PROPERTIES.dup

        system_properties.each_with_object({}) do |system_property, hash|
          hash[system_property.property_name] = system_property.value(T.cast(repository, ::Repository)) if system_property
        end
      end
    end

    sig { params(system_properties: T::Hash[String, String], condition:  T::Array[PropertyParam], any_match: T::Boolean).returns(T::Boolean) }
    def self.evaluate(system_properties, condition, any_match: false)
      if any_match
        condition.any? do |condition_part|
          evaluate_part(system_properties, condition_part["name"], condition_part["property_values"])
        end
      else
        condition.all? do |condition_part|
          evaluate_part(system_properties, condition_part["name"], condition_part["property_values"])
        end
      end
    end

    sig { params(properties: T::Hash[String, String], property_name: String, expected_values: T::Array[String]).returns(T::Boolean) }
    private_class_method def self.evaluate_part(properties, property_name, expected_values)
      effective_values = properties[property_name]

      (Array(expected_values).map(&:downcase) & Array(effective_values).map(&:downcase)).present?
    end

    sig { params(repository: Repositories::IRepository, property_name: String).returns(T.nilable(CustomPropertiesCore::PropertyValue)) }
    private_class_method def self.get_repository_system_property(repository, property_name)
      system_properties = get_repository_system_properties(repository)
      system_properties[property_name]
    end

    sig { params(repository: Repositories::IRepository).returns(T::Hash[String, T.nilable(CustomPropertiesCore::PropertyValue)]) }
    private_class_method def self.get_repository_system_properties(repository)
      @system_properties_by_repository ||= {}

      # Cache system properties per repository to avoid repeated lookups
      unless @system_properties_by_repository.key?(repository.id)
        @system_properties_by_repository[repository.id] = Repositories.domain.custom_properties.repo_system_properties([repository]).fetch(repository, {})
      end

      @system_properties_by_repository[repository.id]
    end
  end
end
