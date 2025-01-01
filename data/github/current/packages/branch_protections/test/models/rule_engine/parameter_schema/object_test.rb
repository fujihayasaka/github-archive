# typed: true
# frozen_string_literal: true

require "test_helper"

class RuleEngineParameterSchemaObjectTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository)
  end

  setup do
    @schema = RuleEngine::ParameterSchema::Object.root
    @schema.add_field(RuleEngine::ParameterSchema::Field.new(name: "foo", display_name: "Foo", description: "Foo", type: :string, required: true))
    @schema.add_field(RuleEngine::ParameterSchema::Field.new(name: "bar", display_name: "Bar", description: "Bar", type: :string, required: false))
    @schema.add_field(RuleEngine::ParameterSchema::Field.new(name: "org_foo", display_name: "Org Foo", description: "Org Foo", type: :string, required: true, org_only: true))
    @schema.add_field(RuleEngine::ParameterSchema::Field.new(name: "org_bar", display_name: "Org Bar", description: "Org Bar", type: :string, required: false, org_only: true))
  end

  test "enforces required fields" do
    value = {}
    context = RuleEngine::ParameterSchema::ValidationContext.new(value, nil)
    assert_equal [{ error_code: :missing, message: "Missing required parameter `foo`", field: "foo" }, { error_code: :missing, message: "Missing required parameter `org_foo`", field: "org_foo" }], @schema.validate_parameters(context, value)
  end

  test "ignores excluded optional fields" do
    value = { "foo" => "bar", "org_foo" => "bar" }
    context = RuleEngine::ParameterSchema::ValidationContext.new(value, nil)
    refute @schema.validate_parameters(context, value).any?
  end

  test "restricts extraneous fields" do
    value = { "foo" => "bar", "org_foo" => "bar", "baz" => "qux" }
    context = RuleEngine::ParameterSchema::ValidationContext.new(value, nil)
    assert_equal [{ error_code: :unexpected_field, message: "Unexpected parameter `baz`", value: "baz" }], @schema.validate_parameters(context, value)
  end

  test "validates multiple fields" do
    value = { "baz" => "qux" }
    context = RuleEngine::ParameterSchema::ValidationContext.new(value, nil)

    errors = @schema.validate_parameters(context, value)

    assert_equal 3, errors.size
    assert errors.any? { |error| error[:message].include?("Missing required parameter `foo`") }
    assert errors.any? { |error| error[:message].include?("Missing required parameter `org_foo`") }
    assert errors.any? { |error| error[:message].include?("Unexpected parameter `baz`") }
  end

  test "set default values for source" do
    parameters = { "bar" => "baz" }
    @schema.apply_defaults_for_source(@repo, parameters)

    assert_equal "", parameters["foo"]
    assert_equal "baz", parameters["bar"]
    assert_equal "", parameters["org_foo"]
    assert_nil parameters["org_bar"]
  end

  test "validates field using custom validator" do
    @schema.add_field(RuleEngine::ParameterSchema::Field.new(name: "custom", display_name: "Custom", description: "Custom", type: :string, validator: method(:custom_validator)))

    value = { "foo" => "bar", "org_foo" => "bar", "custom" => "custom" }
    context = RuleEngine::ParameterSchema::ValidationContext.new(value, nil)

    assert_equal [{ error_code: :invalid, message: "Test", field: "custom" }], @schema.validate_parameters(context, value)
  end

  test "validates array using custom validator" do
    @schema.add_field(RuleEngine::ParameterSchema::Array.new(name: "custom", content_type: :string, display_name: "Custom", description: "Custom", validator: method(:custom_validator)))

    value = { "foo" => "bar", "org_foo" => "bar", "custom" => ["custom"] }
    context = RuleEngine::ParameterSchema::ValidationContext.new(value, nil)

    assert_equal [{ error_code: :invalid, message: "Invalid parameter custom: Test", sub_errors: [{ error_code: :test, message: "Test" }], field: "custom" }], @schema.validate_parameters(context, value)
  end

  test "parameter is visible when there is no feature flag" do
    flag = :test_param_feature_flag_visibility
    @schema.add_field(RuleEngine::ParameterSchema::Field.new(name: "feature-flagged", display_name: "Custom", description: "Custom", type: :string))

    @schema.fields.find { |f| f.name == "feature-flagged" }.tap do |field|
      assert field.is_visible_by_source?(@repo)
    end
  end

  test "parameter is visible when the feature flag is enabled" do
    flag = :test_param_feature_flag_visibility
    enable_feature_flag(flag, @repo)
    @schema.add_field(RuleEngine::ParameterSchema::Field.new(name: "feature-flagged", display_name: "Custom", description: "Custom", type: :string, feature_flag: flag))

    @schema.fields.find { |f| f.name == "feature-flagged" }.tap do |field|
      assert field.is_visible_by_source?(@repo)
    end
  end

  test "parameter is not visible when the feature flag is disabled" do
    flag = :test_param_feature_flag_visibility
    disable_feature_flag(flag, @repo)
    @schema.add_field(RuleEngine::ParameterSchema::Field.new(name: "feature-flagged", display_name: "Custom", description: "Custom", type: :string, feature_flag: flag))

    @schema.fields.find { |f| f.name == "feature-flagged" }.tap do |field|
      refute field.is_visible_by_source?(@repo)
    end
  end

  context "allowed_values" do
    test "validates fail when value is not in the allowed_values" do
      @schema.add_field(RuleEngine::ParameterSchema::Field.new(name: "baz", display_name: "Baz", description: "Baz", type: :string, required: false, allowed_values: %w[boogle zork], default_value: "boogle"))

      value = { "foo" => "bar", "org_foo" => "bar", "baz" => "qux" }
      context = RuleEngine::ParameterSchema::ValidationContext.new(value, nil)

      assert_equal [{ error_code: :invalid, message: "Expected value to be one of boogle, zork, got qux", field: "baz" }], @schema.validate_parameters(context, value)
    end

    test "validates pass when value is in the allowed_values" do
      @schema.add_field(RuleEngine::ParameterSchema::Field.new(name: "baz", display_name: "Baz", description: "Baz", type: :string, required: false, allowed_values: %w[boogle zork], default_value: "boogle"))

      value = { "foo" => "bar", "org_foo" => "bar", "baz" => "boogle" }
      context = RuleEngine::ParameterSchema::ValidationContext.new(value, nil)

      assert_empty @schema.validate_parameters(context, value)
    end
  end

  test "#transform_parameters!" do
    schema = RuleEngine::ParameterSchema::Object.root(
      transform_fn: -> (params) do
        params["new_param"] = params["foo"].strip
      end
    )

    schema.add_field(RuleEngine::ParameterSchema::Field.new(
      name: "baz",
      display_name: "Baz",
      description: "Baz",
      type: :string,
      required: false,
      default_value: "boogle"),
    )

    parameters = { "foo" => "bar ", "org_foo" => "bar ", "baz" => "boogle " }

    schema.transform_parameters!(parameters)

    # We have a new param that has been transformed
    assert_equal "bar", parameters["new_param"]
    # The original param is still there
    assert_equal "bar ", parameters["foo"]
    assert_equal "boogle ", parameters["baz"]
  end

  private

  def custom_validator(context, params, errors)
    errors << {
      error_code: :test,
      message: "Test"
    }
  end
end
