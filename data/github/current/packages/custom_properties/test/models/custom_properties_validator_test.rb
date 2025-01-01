# typed: true
# frozen_string_literal: true

require "test_helper"

class CustomPropertiesValidatorTest < GitHub::TestCase
  include CustomPropertiesValidator

  setup do
    enable_feature_flag(:custom_properties_regex)

    org = create :organization

    definition_env = create :custom_property_definition, :single_select, property_name: "environment", allowed_values: ["production"], source: org
    definition_cost_center = create :custom_property_definition, property_name: "cost_center", source: org
    definition_true_false = create :custom_property_definition, :true_false, property_name: "true_false", source: org
    definition_platform = create :custom_property_definition, :multi_select, property_name: "platform", allowed_values: %w[ios web], source: org
    definition_regex = create :custom_property_definition, :string, property_name: "regex", config: { regex: "[0-9]+" }, source: org

    @definitions = [definition_env, definition_cost_center, definition_true_false, definition_platform, definition_regex]
    @definitions_hash = @definitions.index_by(&:property_name).transform_keys(&:downcase)
  end

  context "#validate_schema" do
    test "should return empty array if no errors" do
      assert_equal validate_schema(@definitions_hash, "environment" => "production"), []
    end

    test "should return empty if nil value" do
      assert_equal validate_schema(@definitions_hash, "environment" => nil), []
    end

    test "validates if property is defined" do
      errors = validate_schema(@definitions_hash, "environment" => "production", "invalid" => "bla")

      assert_equal errors.length, 1
      assert_equal T.must(errors[0]).property_name, "invalid"
      assert_equal T.must(errors[0]).error_message, "Unexpected property 'invalid'"
    end

    test "validates if value is allowed" do
      errors = validate_schema(@definitions_hash, "environment" => "development", "cost_center" => "east")

      assert_equal errors.length, 1
      assert_equal T.must(errors[0]).property_name, "environment"
      assert_equal T.must(errors[0]).error_message, "Value 'development' is not allowed for property 'environment'"
    end

    test "validates multi_select values" do
      errors = validate_schema(@definitions_hash, "platform" => %w(android macOS))

      assert_equal errors.length, 1
      assert_equal T.must(errors[0]).property_name, "platform"
      assert_equal T.must(errors[0]).error_message, "Values 'android, macOS' are not allowed for property 'platform'"
    end

    test "validates true_false values" do
      errors = validate_schema(@definitions_hash, "true_false" => "dunno")

      assert_equal errors.length, 1
      assert_equal T.must(errors[0]).property_name, "true_false"
      assert_equal T.must(errors[0]).error_message, "Value 'dunno' is not allowed for property 'true_false'"
    end

    test "returns errors when value type is unsupported" do
      errors = validate_schema(@definitions_hash, { "platform" => "value" }).map(&:error_message)
      assert_equal ["Property 'platform' value must be a list of strings"], errors
    end

    test "returns errors if values are not uniq" do
      errors = validate_schema(@definitions_hash, { "platform" => %w(ios ios ios) }).map(&:error_message)
      assert_equal ["Property 'platform' values must be distinct"], errors
    end

    test "no errors for empty or nil value" do
      assert_equal validate_schema(@definitions_hash, "environment" => ""), []
      assert_equal validate_schema(@definitions_hash, "environment" => nil), []
    end

    test "returns errors when value does not match regex" do
      errors = validate_schema(@definitions_hash, { "regex" => "abc" }).map(&:error_message)
      assert_equal ["Property 'regex' must match regular expression [0-9]+"], errors
    end

    test "saves valid regex value" do
      errors = validate_schema(@definitions_hash, { "regex" => "[0-9]+" }).map(&:error_message)
      assert_empty errors
    end
  end

  context "#validate_values" do
    context "multi_select" do
      test "values can only be a list of strings" do
        errors = validate_values("platform" => [:val]).map(&:error_message)
        assert_equal ["Property 'platform' values must be strings"], errors
      end

      test "returns errors when value is too long" do
        value = "a" * (Public::MAX_LENGTH + 1)
        errors = validate_values({ "platform" => [value] }).map(&:error_message)
        assert_equal ["Property 'platform' value is too long"], errors
      end

      test "returns errors when value contains chars invalid" do
        value = '"'
        errors = validate_values({ "platform" => [value] }).map(&:error_message)
        assert_equal ["Property 'platform' value has invalid characters: \""], errors
      end
    end

    context "string" do
      test "string: returns errors when value type is unsupported" do
        errors = validate_values({ "security" => :value }).map(&:error_message)
        assert_equal ["Property 'security' values must be strings"], errors
      end

      test "returns errors when value is too long" do
        value = "a" * (Public::MAX_LENGTH + 1)
        errors = validate_values({ "security" => value }).map(&:error_message)
        assert_equal ["Property 'security' value is too long"], errors
      end

      test "returns errors when value contains chars invalid" do
        value = '"'
        errors = validate_values({ "security" => value }).map(&:error_message)
        assert_equal ["Property 'security' value has invalid characters: \""], errors
      end
    end

    test "no errors for empty or nil value" do
      assert_equal validate_values({ "security" => "" }), []
      assert_equal validate_values({ "security" => nil }), []
    end
  end

  context "validate_properties" do
    test "deduplicates validation errors" do
      errors = validate_properties(@definitions, { "platform" => [:val, nil, ["test"]] }).map(&:error_message)
      assert_equal [
        "Values 'val, , test' are not allowed for property 'platform'",
        "Property 'platform' values must be strings"
      ], errors
    end

    test "validates using case-insensitive schema lookup" do
      assert_equal validate_properties([@definitions.first], { "ENVIRONMENT" => "production" }), []
    end
  end

  context "validate_allowed_values" do
    %w[single_select multi_select].each do |value_type|
      test "returns empty array if value is allowed (#{value_type})" do
        assert_empty validate_allowed_values("environment", value_type, %w[production test], "production")
      end

      test "returns error if value is not allowed (#{value_type})" do
        allowed_values = value_type == "true_false" ? nil : %w[production test]

        assert_equal validate_allowed_values("environment", value_type, allowed_values, "development").map(&:error_message), ["Value 'development' is not allowed for property 'environment'"]
      end
    end

    test "returns empty array if value is allowed (true_false)" do
      assert_empty validate_allowed_values("true_false", "true_false", nil, "true")
    end

    test "returns error if value is not allowed (true_false)" do
      assert_equal validate_allowed_values("true_false", "true_false", nil, "development").map(&:error_message), ["Value 'development' is not allowed for property 'true_false'"]
    end
  end
end
