# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryRulesetsSystemPropertyDescriptorTests < GitHub::TestCase
  include RepositoryRulesets

  test "initialize" do
    org = create :organization
    smile = create :repository, owner: org, name: "smile"

    system_definition = SystemPropertyDescriptor.new(
      property_name: "fork",
      value_type: "single_select",
      allowed_values: %w[true false],
      value_accessor: ->(repository) { repository.name },
      icon: "repo-forked",
      display_name: "Fork"
    )

    assert_equal "fork", system_definition.property_name
    assert_equal "single_select", system_definition.value_type
    assert_equal %w[true false], system_definition.get_allowed_values
    assert_equal "smile", system_definition.value(smile)
    assert_equal "repo-forked", system_definition.icon
    assert_equal "Fork", system_definition.display_name
    assert_equal "system", system_definition.source
  end

  context "validate" do
    test "when validator" do
      system_definition = SystemPropertyDescriptor.new(
        property_name: "language",
        value_type: "single_select",
        value_accessor: ->(repository) { repository.name },
        icon: "code",
        display_name: "Language",
        validator: ->(value, _context) { value == "ruby" }
      )

      refute system_definition.validate(["Spanish"])
      assert system_definition.validate(["ruby"])
    end

    test "when no validator and has allowed_values" do
      system_definition = SystemPropertyDescriptor.new(
        property_name: "language",
        value_type: "single_select",
        allowed_values: %w[ruby go python],
        value_accessor: ->(repository) { repository.name },
        icon: "code",
        display_name: "Language"
      )

      refute system_definition.validate(["Spanish"])
      assert system_definition.validate(["ruby"])
    end

    test "when no validator and type string" do
      system_definition = SystemPropertyDescriptor.new(
        property_name: "language",
        value_type: "string",
        value_accessor: ->(repository) { repository.name },
        icon: "code",
        display_name: "Language",
      )

      assert system_definition.validate(["Spanish"])
    end

    test "when no validator and type true_false" do
      system_definition = SystemPropertyDescriptor.new(
        property_name: "language",
        value_type: "true_false",
        value_accessor: ->(repository) { repository.name },
        icon: "code",
        display_name: "Language",
      )

      refute system_definition.validate(["Spanish"])
      assert system_definition.validate(["true"])
      assert system_definition.validate(["false"])
    end

    test "when no allowed_values or validator (wrong usage)" do
      system_definition = SystemPropertyDescriptor.new(
        property_name: "language",
        value_type: "single_select",
        value_accessor: ->(repository) { repository.name },
        icon: "code",
        display_name: "Language",
      )

      refute system_definition.validate(["Spanish"])
      refute system_definition.validate(["ruby"])
    end

  end
end
