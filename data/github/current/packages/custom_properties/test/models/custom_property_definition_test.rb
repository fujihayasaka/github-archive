# typed: true
# frozen_string_literal: true

require "test_helper"

class CustomPropertyDefinitionTest < GitHub::TestCase
  setup do
    @business = create :business
    @org = create :organization, business: @business

    @biz_def = create :custom_property_definition, source: @business, property_name: "prop_a"
    @biz_org_def = create :custom_property_definition, source: @org, property_name: "prop_b"
  end

  context "defined_by" do
    test "returns definitions for an organization without enterprise" do
      org = create(:organization)
      definition = create :custom_property_definition, source: org

      assert_equal [definition], CustomPropertyDefinition.defined_by(org)
    end

    test "returns definitions for an enterprise org" do
      assert_equal [@biz_org_def], CustomPropertyDefinition.defined_by(@org)
    end

    test "returns definitions for an enterprise" do
      assert_equal [@biz_def], CustomPropertyDefinition.defined_by(@business)
    end

    test "raises for unknown source class" do
      assert_raises TypeError do
        CustomPropertyDefinition.for(create(:repository))
      end
    end
  end

  context "for" do
    test "returns definitions for an organization without enterprise" do
      org = create(:organization)
      definition = create :custom_property_definition, source: org

      assert_equal [definition], CustomPropertyDefinition.for(org)
    end

    test "returns definitions for an enterprise org" do
      assert_same_elements [@biz_def, @biz_org_def], CustomPropertyDefinition.for(@org)
    end

    test "returns definitions for an enterprise" do
      assert_equal [@biz_def], CustomPropertyDefinition.for(@business)
    end

    test "raises for unknown source class" do
      assert_raises TypeError do
        CustomPropertyDefinition.for(create(:repository))
      end
    end
  end

  context "validation" do
    context "validate_default_value_type" do
      test "raises if default value of 'multi_select' is not an array" do
        error = assert_raises ActiveRecord::RecordInvalid do
          CustomPropertyDefinition.create!(
            source: @org,
            property_name: "platform",
            value_type: :multi_select,
            allowed_values: %w[ios web macOS],
            required: true,
            config: { default_value: "ios" }
          )
        end

        assert_equal "Validation failed: Default value must be an array of strings for 'multi_select' property", error.message
      end

      test "raises if default value of 'string' is not a string" do
        error = assert_raises ActiveRecord::RecordInvalid do
          CustomPropertyDefinition.create!(
            source: @org,
            property_name: "version",
            value_type: :string,
            required: true,
            config: { default_value: %w[1.0 2.0] }
          )
        end

        assert_equal "Validation failed: Default value must be a string for 'string' property", error.message
      end

      test "raises if default value of 'single_select' is not a string" do
        error = assert_raises ActiveRecord::RecordInvalid do
          CustomPropertyDefinition.create!(
            source: @org,
            property_name: "env",
            value_type: :single_select,
            required: true,
            allowed_values: %w[prod test dev],
            config: { default_value: %w[prod test] }
          )
        end

        assert_equal "Validation failed: Default value must be a string for 'single_select' property", error.message
      end

      test "raises if default values of 'true_false' is not a string" do
        error = assert_raises ActiveRecord::RecordInvalid do
          CustomPropertyDefinition.create!(
            source: @org,
            property_name: "is_legacy",
            value_type: :true_false,
            required: true,
            config: { default_value: %w[true] }
          )
        end

        assert_equal "Validation failed: Default value must be a string for 'true_false' property", error.message
      end
    end
  end

  test "should not save without org" do
    assert_raises ActiveRecord::NotNullViolation do
      CustomPropertyDefinition.create!(property_name: "environment", value_type: :string)
    end
  end

  test "should not save without property_name" do
    assert_raises ActiveRecord::RecordInvalid do
      CustomPropertyDefinition.create!(source: @org, value_type: :string)
    end

    assert_raises ActiveRecord::RecordInvalid do
      CustomPropertyDefinition.create!(source: @org, property_name: "", value_type: :string)
    end
  end

  [:string, :single_select].each do |value_type|
    test "should not save a required-#{value_type} definition without default_value" do
      error = assert_raises ActiveRecord::RecordInvalid do
        CustomPropertyDefinition.create!(
          source: @org,
          property_name: "environment",
          value_type: value_type,
          allowed_values: (%w[prod dev] if value_type == :single_select),
          required: true
        )
      end
      assert_equal "Validation failed: Default value must be present", error.message
    end
  end

  test "should not save single_select if default value is not in allowed values" do
    exception = assert_raises ActiveRecord::RecordInvalid do
      CustomPropertyDefinition.create!(
      source: @org,
      property_name: "environment",
      allowed_values: %w[prod dev],
      value_type: :single_select,
      required: true,
      config: { default_value: "test" }
    )
    end
    assert_equal "Validation failed: Default value must be part of the allowed values", exception.message
  end

  test "should not save multi_select if default values are not in allowed values" do
    exception = assert_raises ActiveRecord::RecordInvalid do
      CustomPropertyDefinition.create!(
      source: @org,
      property_name: "platform",
      allowed_values: %w[ios web macOS],
      value_type: :multi_select,
      required: true,
      config: { default_value: %w[ios web android] }
    )
    end
    assert_equal "Validation failed: Default value must be part of the allowed values", exception.message
  end

  [:string, :single_select].each do |value_type|
    test "should not save a non-required-#{value_type} definition with default_value" do
      exception = assert_raises ActiveRecord::RecordInvalid do
        CustomPropertyDefinition.create!(source: @org,
          property_name: "environment",
          required: false,
          value_type: value_type,
          allowed_values: (%w[prod dev] if value_type == :single_select),
          config: { default_value: "prod" },
        )
      end
      assert_equal "Validation failed: Default value must be empty", exception.message
    end
  end

  test "should not save a default value that doesn't match regex" do
    enable_feature_flag(:custom_properties_regex)

    exception = assert_raises ActiveRecord::RecordInvalid do
      CustomPropertyDefinition.create!(source: @org,
        property_name: "environment",
        required: true,
        value_type: :string,
        config: { default_value: "123", regex: "abc" },
      )
    end
    assert_equal "Validation failed: Default value must match regular expression abc", exception.message
  end

  test "saves a default value that matches regex" do
    enable_feature_flag(:custom_properties_regex)

    assert CustomPropertyDefinition.create!(source: @org,
      property_name: "environment",
      required: true,
      value_type: :string,
      config: { default_value: "abc", regex: "abc" },
    )
  end

  test "should save property_name as a string" do
    CustomPropertyDefinition.create!(source: @org, property_name: 13, value_type: :string)
    assert_equal T.must(CustomPropertyDefinition.last).property_name, "13"
  end

  [:string, :single_select].each do |value_type|
    test "should save a required-#{value_type} definition with default_value is provided" do
      assert CustomPropertyDefinition.create!(
        source: @org,
        property_name: "environment",
        value_type: value_type,
        required: true,
        allowed_values: (%w[prod dev] if value_type == :single_select),
        config: { default_value: "prod" }
      )
    end
  end

  test "can save" do
    assert CustomPropertyDefinition.create!(source: @org, property_name: "environment", value_type: :string)
  end

  test "reads correct default_value" do
    definition = CustomPropertyDefinition.create!(
      source: @org,
      property_name: "version",
      value_type: "string",
      required: true,
      config: { default_value: "v2.0" }
    )

    assert definition

    assert_equal definition.config, { "default_value" => "v2.0" }
    assert_equal definition.default_value, "v2.0"
  end

  [:string, :single_select].each do |value_type|
    test "non-required is by default when creating a #{value_type} definion" do
      definition = CustomPropertyDefinition.create!(
        source: @org,
        property_name: "environment",
        value_type: value_type,
        allowed_values: (%w[prod dev] if value_type == :single_select)
      )
      refute definition.required?
    end
  end

  test "can save when passing source" do
    assert CustomPropertyDefinition.create!(source: @org, property_name: "environment", value_type: :string)
    assert CustomPropertyDefinition.create!(source: @business, property_name: "biz_environment", value_type: :string)
  end

  test "raises if unsupported source class" do
    assert_raises TypeError do
      CustomPropertyDefinition.create!(source: create(:repository), property_name: "environment", value_type: :string)
    end
  end

  test "can save largest allowed name" do
    key75 = "a" * 75
    assert CustomPropertyDefinition.create!(source: @org, property_name: key75, value_type: :string)
  end

  test "can save with allowed characters" do
    assert CustomPropertyDefinition.create!(source: @org, property_name: "cost_center", value_type: :string)
    assert CustomPropertyDefinition.create!(source: @org, property_name: "a11y#team", value_type: :string)
    assert CustomPropertyDefinition.create!(source: @org, property_name: "team$one-", value_type: :string)
  end

  test "should not save if name is too long" do
    exception = assert_raises ActiveRecord::RecordInvalid do
      key76 = "a" * 76
      CustomPropertyDefinition.create!(source: @org, property_name: key76, value_type: :string)
    end

    assert_equal "Validation failed: Property name is too long (maximum is 75 characters)", exception.message
  end

  test "should not save if name has unallowed characters" do
    bad_names = ["a b", "a:b", "a=b", "a+b", "a*b"]
    bad_names.map do |name|
      exception = assert_raises ActiveRecord::RecordInvalid do
        CustomPropertyDefinition.create!(source: @org, property_name: name, value_type: :string)
      end
      assert_equal "Validation failed: Property name is invalid", exception.message
    end
  end

  test "raises if incorrect type is used for allowed values field" do
    exception = assert_raises ActiveRecord::RecordInvalid do
      CustomPropertyDefinition.create!(
        source: @org,
        property_name: "env",
        allowed_values: "string value",
        value_type: :single_select
      )
    end

    assert_equal exception.message, "Validation failed: Allowed values must be an array of strings"
  end

  test "raises if too many allowed values" do
    exception = assert_raises ActiveRecord::RecordInvalid do
      CustomPropertyDefinition.create!(
        source: @org,
        property_name: "env",
        allowed_values: Array.new(201) { |i| "value-#{i}" },
        value_type: :single_select
      )
    end

    assert_equal exception.message, "Validation failed: Allowed values must be maximum 200 values"
  end

  test "raises if value_type is not set" do
    exception = assert_raises ActiveRecord::RecordInvalid do
      CustomPropertyDefinition.create!(
        source: @org,
        property_name: "env",
        allowed_values: %w[prod test],
      )
    end

    assert_equal exception.message, "Validation failed: Value type can't be blank"
  end

  test "raises if value_type is empty" do
    exception = assert_raises ActiveRecord::RecordInvalid do
      CustomPropertyDefinition.create!(
        source: @org,
        property_name: "env",
        value_type: "",
      )
    end

    assert_equal exception.message, "Validation failed: Value type can't be blank"
  end

  test "raises if value_type is unknown" do
    exception = assert_raises ArgumentError do
      CustomPropertyDefinition.create!(
        source: @org,
        property_name: "env",
        value_type: "foobar",
      )
    end

    assert_equal exception.message, "'foobar' is not a valid value_type"
  end

  test "raises if allowed values are not strings" do
    exception = assert_raises ActiveRecord::RecordInvalid do
      CustomPropertyDefinition.create!(
        source: @org,
        property_name: "env",
        allowed_values: [1],
        value_type: :single_select
      )
    end

    assert_equal exception.message, "Validation failed: Allowed values '1' must be a string"
  end

  test "raises if allowed values have invalid characters" do
    exception = assert_raises ActiveRecord::RecordInvalid do
      CustomPropertyDefinition.create!(
        source: @org,
        property_name: "env",
        allowed_values: ["no🦦unicode"],
        value_type: :single_select
      )
    end

    assert_equal exception.message, "Validation failed: Allowed values 'no🦦unicode' contains invalid characters: 🦦"
  end

  test "raises if allowed value is too long" do
    long_value = "a" * 76
    exception = assert_raises ActiveRecord::RecordInvalid do
      CustomPropertyDefinition.create!(
        source: @org,
        property_name: "env",
        allowed_values: [long_value],
        value_type: :single_select
      )
    end

    assert_equal exception.message, "Validation failed: Allowed values '#{long_value}' must be at most 75 characters"
  end

  test "raises if allowed values is empty" do
    exception = assert_raises ActiveRecord::RecordInvalid do
      CustomPropertyDefinition.create!(
        source: @org,
        property_name: "env",
        allowed_values: [],
        value_type: :single_select
      )
    end

    assert_equal exception.message, "Validation failed: Allowed values must contain at least one value"
  end

  test "raises if value_type is string and contains allowed values" do
    exception = assert_raises ActiveRecord::RecordInvalid do
      CustomPropertyDefinition.create!(
        source: @org,
        property_name: "env",
        allowed_values: %w[test prod],
        value_type: :string
      )
    end

    assert_equal exception.message, "Validation failed: Allowed values must be nil if value_type is string"
  end

  test "raises if allowed values contain duplicates after stripping whitespace and downcasing" do
    exception = assert_raises ActiveRecord::RecordInvalid do
      CustomPropertyDefinition.create!(
        source: @org,
        property_name: "env",
        allowed_values: ["Prod", " prod", "prod unique"],
        value_type: :single_select
      )
    end

    assert_equal exception.message, "Validation failed: Allowed values contains duplicates: Prod"
  end

  test "validates default value with no allowed values provided" do
    exception = assert_raises ActiveRecord::RecordInvalid do
      CustomPropertyDefinition.create!(
        source: @org,
        property_name: "env",
        value_type: :single_select,
        required: true,
        config: { default_value: "prod" }
      )
    end

    assert_equal exception.message, "Validation failed: Allowed values must be present if value_type is single_select, Default value must be part of the allowed values"
  end

  %i"single_select multi_select".each do |value_type|
    test "ensure uniq of allowed_values for #{value_type}" do
      exception = assert_raises ActiveRecord::RecordInvalid do
        CustomPropertyDefinition.create!(
          source: @org,
          property_name: "language",
          allowed_values: %w[ruby python java ruby],
          value_type:
        )
      end

      assert_equal exception.message, "Validation failed: Allowed values contains duplicates: ruby"
    end
  end

  test "can save true_false type" do
    definition = CustomPropertyDefinition.create(
      source: @org,
      property_name: "thebool",
      value_type: :true_false
    )

    assert definition.persisted?
  end

  test "true_false type requires nil allowed values" do
    definition = CustomPropertyDefinition.create(
      source: @org,
      property_name: "thebool",
      value_type: :true_false,
      allowed_values: %w[not, allowed]
    )

    assert_equal definition.errors.full_messages, ["Allowed values must be nil if value_type is true_false"]
  end

  test "can save regex for text properties" do
    definition = CustomPropertyDefinition.create(
      source: @org,
      property_name: "regex",
      value_type: :string,
      config: {
        default_value: nil,
        regex: "abc123"
      }
    )

    if GitHub.flipper[:custom_properties_regex].enabled?
      assert definition.persisted?
    else
      assert_equal definition.errors.full_messages, ["Regex is not supported"]
    end
  end

  test "raises for invalid regex" do
    enable_feature_flag(:custom_properties_regex)

    definition = CustomPropertyDefinition.create(
      source: @org,
      property_name: "regex",
      value_type: :string,
      config: {
        default_value: nil,
        regex: "(abc123"
      }
    )

    assert_equal definition.errors.full_messages, ["Regex must be a valid regex pattern"]
  end

  test "raises for regex when not a string type" do
    enable_feature_flag(:custom_properties_regex)

    definition = CustomPropertyDefinition.create(
      source: @org,
      property_name: "single_select",
      allowed_values: %w[prod dev],
      value_type: :single_select,
      config: {
        default_value: nil,
        regex: "abc123"
      }
    )

    assert_equal definition.errors.full_messages, ["Regex is only supported on string properties"]
  end

  context "instrumentation" do
    [:string, :single_select].each do |value_type|
      [true, false].each do |required|
        test "should audit log when creating a #{required}-#{value_type} definition" do
          events = subscribe "custom_property_definition.create"

          definition = create :custom_property_definition,
            value_type,
            source: @org,
            property_name: "environment",
            description: "This is a description for the environment definition",
            allowed_values: (%w[prod dev] if value_type == :single_select),
            required: required,
            default_value: ("prod" if required)

          refute_nil event = events.pop, "an event was expected"

          expected_payload = {
            definition_id: definition.id,
            property_name: "environment",
            org: @org.display_login,
            org_id: @org.id,
            value_type: value_type.to_s,
            required: required,
            default_value: ("prod" if required),
            description: "This is a description for the environment definition",
            allowed_values: (%w[prod dev] if value_type == :single_select),
          }
          assert_equal expected_payload, event.payload
        end

        test "should audit log when deleting a #{required}-#{value_type} definition" do
          definition = create :custom_property_definition,
            value_type,
            source: @org,
            property_name: "environment",
            description: "This is a description for the environment definition",
            allowed_values: (%w[prod dev] if value_type == :single_select),
            required: required,
            default_value: ("prod" if required)

          events = subscribe "custom_property_definition.destroy"
          definition.destroy!

          refute_nil event = events.pop, "an event was expected"

          expected_payload = {
            definition_id: definition.id,
            property_name: "environment",
            org: @org.display_login,
            org_id: @org.id,
            value_type: value_type.to_s,
            required: required,
            default_value: ("prod" if required),
            allowed_values: (%w[prod dev] if value_type == :single_select),
            description: "This is a description for the environment definition"
          }
          assert_equal expected_payload, event.payload
        end

        test "should audit log when creating a #{required}-#{value_type} definition for business" do
          events = subscribe "custom_property_definition.create"

          definition = create :custom_property_definition,
            value_type,
            source: @business,
            property_name: "biz_environment",
            description: "This is a description for the environment definition",
            allowed_values: (%w[prod dev] if value_type == :single_select),
            required: required,
            default_value: ("prod" if required)

          refute_nil event = events.pop, "an event was expected"

          expected_payload = {
            definition_id: definition.id,
            property_name: "biz_environment",
            business: @business.display_login,
            business_id: @business.id,
            value_type: value_type.to_s,
            required: required,
            default_value: ("prod" if required),
            description: "This is a description for the environment definition",
            allowed_values: (%w[prod dev] if value_type == :single_select),
          }
          assert_equal expected_payload, event.payload
        end

        test "should audit log when deleting a #{required}-#{value_type} definition for business" do
          definition = create :custom_property_definition,
            value_type,
            source: @business,
            property_name: "biz_environment",
            description: "This is a description for the environment definition",
            allowed_values: (%w[prod dev] if value_type == :single_select),
            required: required,
            default_value: ("prod" if required)

          events = subscribe "custom_property_definition.destroy"
          definition.destroy!

          refute_nil event = events.pop, "an event was expected"

          expected_payload = {
            definition_id: definition.id,
            property_name: "biz_environment",
            business: @business.display_login,
            business_id: @business.id,
            value_type: value_type.to_s,
            required: required,
            default_value: ("prod" if required),
            allowed_values: (%w[prod dev] if value_type == :single_select),
            description: "This is a description for the environment definition"
          }
          assert_equal expected_payload, event.payload
        end
      end
    end

    test "should NOT audit at repo level when deleting a definition with associated values" do
      repo = create :repository, owner: @org

      definition = create :custom_property_definition, source: @org, property_name: "environment"
      create :custom_property_value, definition: definition, target: repo, value: "production"

      org_events = subscribe "custom_property_definition.destroy"
      repo_events = subscribe "custom_property_value.destroy"
      definition.destroy!

      refute_nil org_events.pop
      assert_nil repo_events.pop
    end

    [true, false].each do |required|
      test "should audit log when updating the allowed_values for a #{required} definition" do
        definition = create :custom_property_definition,
          :single_select,
          source: @org,
          property_name: "environment",
          allowed_values: %w[prod dev],
          required: required,
          default_value: ("prod" if required)

        events = subscribe "custom_property_definition.update"
        definition.update!(allowed_values: %w[prod dev test])

        refute_nil event = events.pop, "an event was expected"

        expected_payload = {
          definition_id: definition.id,
          property_name: "environment",
          org: @org.display_login,
          org_id: @org.id,
          old_allowed_values: %w[prod dev],
          allowed_values: %w[prod dev test]
        }

        assert_equal expected_payload, event.payload
      end
    end

    test "should audit log when updating definition for business" do
      definition = create :custom_property_definition,
        :single_select,
        source: @business,
        property_name: "biz_environment",
        allowed_values: %w[prod dev]

      events = subscribe "custom_property_definition.update"
      definition.update!(allowed_values: %w[prod dev test])

      refute_nil event = events.pop, "an event was expected"

      expected_payload = {
        definition_id: definition.id,
        property_name: "biz_environment",
        business: @business.display_login,
        business_id: @business.id,
        old_allowed_values: %w[prod dev],
        allowed_values: %w[prod dev test],
      }

      assert_equal expected_payload, event.payload
    end

    [true, false].each do |required|
      test "audit log when updating the required property (#{required} to #{!required})" do
        definition = create :custom_property_definition,
          :single_select,
          source: @org,
          property_name: "environment",
          allowed_values: %w[prod dev],
          required: required,
          default_value: ("prod" if required)

        events = subscribe "custom_property_definition.update"
        new_required = !required
        definition.update!(
          required: new_required,
          config: new_required ? { default_value: "prod" } : nil
        )

        refute_nil event = events.pop, "an event was expected"

        expected_payload = {
          definition_id: definition.id,
          property_name: "environment",
          org: @org.display_login,
          org_id: @org.id,
          old_required: required,
          required: new_required,
          old_default_value: ("prod" if required),
          default_value: ("prod" if new_required)
        }

        assert_equal expected_payload, event.payload
      end
    end

    test "audit log when updating default_value" do
      definition = create :custom_property_definition,
        :single_select,
        source: @org,
        property_name: "environment",
        allowed_values: %w[prod dev],
        required: true,
        default_value: "prod"

      events = subscribe "custom_property_definition.update"
      definition.update!(config: { default_value: "dev" })

      refute_nil event = events.pop, "an event was expected"

      expected_payload = {
        definition_id: definition.id,
        property_name: "environment",
        org: @org.display_login,
        org_id: @org.id,
        old_default_value: "prod",
        default_value: "dev"
      }

      assert_equal expected_payload, event.payload
    end

    test "audit log should not log the description update when updating multiple properties" do
      definition = create :custom_property_definition,
        :single_select,
        source: @org,
        property_name: "environment",
        allowed_values: %w[prod dev]

      events = subscribe "custom_property_definition.update"
      definition.update!(description: "This description has been updated", allowed_values: %w[prod dev test])

      refute_nil event = events.pop, "an event was expected"

      expected_payload = {
        definition_id: definition.id,
        property_name: "environment",
        org: @org.display_login,
        org_id: @org.id,
        old_allowed_values: %w[prod dev],
        allowed_values: %w[prod dev test]
      }

      assert_equal expected_payload, event.payload
    end

    test "should not audit log when updating the description" do
      definition = create :custom_property_definition, source: @org

      events = subscribe "custom_property_definition.update"
      definition.update!(description: "This description has been updated")

      assert_empty events
    end

    test "should not audit log when no changes" do
      definition = create :custom_property_definition,
        :single_select,
        source: @org,
        allowed_values: %w[prod dev]

      events = subscribe "custom_property_definition.update"

      definition.update!(allowed_values: %w[prod dev])

      assert_empty events
    end
  end
end
