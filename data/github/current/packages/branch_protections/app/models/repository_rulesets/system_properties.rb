# typed: true
# frozen_string_literal: true

module RepositoryRulesets
  module SystemProperties

    PropertyParam = T.type_alias { { "name" => String, "property_values" => T::Array[String] } }

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

    sig do
      params(repository: ::Repository, property_names: T::Array[String]).returns(T::Hash[String, String])
    end
    private_class_method def self.get_values(repository, property_names)
      system_properties = SYSTEM_PROPERTIES.dup

      property_names.each_with_object({}) do |property_name, hash|
        system_property = system_properties.find { |i| i.property_name == property_name }
        hash[property_name] = system_property.value(repository) if system_property
      end
    end

    sig { params(repository: ::Repository, condition:  T::Array[PropertyParam], any_match: T::Boolean).returns(T::Boolean) }
    def self.evaluate(repository, condition, any_match: false)
      system_properties = get_values(repository, condition.map { |c| c["name"] })

      if any_match
        condition.any? do |condition_part|
          evaluate_part(repository, system_properties, condition_part["name"], condition_part["property_values"])
        end
      else
        condition.all? do |condition_part|
          evaluate_part(repository, system_properties, condition_part["name"], condition_part["property_values"])
        end
      end
    end

    sig { params(repository: ::Repository, properties: T::Hash[String, String], property_name: String, expected_values: T::Array[String]).returns(T::Boolean) }
    private_class_method def self.evaluate_part(repository, properties, property_name, expected_values)
      effective_values = properties[property_name]

      (Array(expected_values).map(&:downcase) & Array(effective_values).map(&:downcase)).present?
    end
  end
end
