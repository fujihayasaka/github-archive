# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::VSCSBillingSchemaTest < GitHub::TestCase
  # The two versions of this schema should stay exactly in sync except for whether or not additional properties are allowed at any level

  setup do
    @plan = create(:codespace_plan)
    @codespaces = create_list(:codespace, 3, plan: @plan)
    @strict_fragment_path = "#/properties/additionalPropertiesDenied"
    @permissive_fragment_path = "#/properties/additionalPropertiesAllowed"
  end

  test "both versions have same number of errors when passed empty data" do
    message = {}
    strict_validation_errors = JSON::Validator.fully_validate(Codespaces::BillingMessageValidator::JSON_SCHEMA_PATH, message, fragment: @strict_fragment_path)
    permissive_validation_errors = JSON::Validator.fully_validate(Codespaces::BillingMessageValidator::JSON_SCHEMA_PATH, message, fragment: @permissive_fragment_path)
    assert_equal strict_validation_errors.length, 6
    assert_equal strict_validation_errors.length, permissive_validation_errors.length
  end

  test "extra params only errors on strict validation" do
    message = FakeVSOServer.messages_for(plan: @plan, codespaces: @codespaces, fields_to_add: { "extraParam" => "extraValue" })
    strict_validation_errors = JSON::Validator.fully_validate(Codespaces::BillingMessageValidator::JSON_SCHEMA_PATH, message, fragment: @strict_fragment_path)
    permissive_validation_errors = JSON::Validator.fully_validate(Codespaces::BillingMessageValidator::JSON_SCHEMA_PATH, message, fragment: @permissive_fragment_path)
    assert_equal strict_validation_errors.length, 3
    assert_equal permissive_validation_errors.length, 0
  end

  test "handles complete data" do
    message = FakeVSOServer.messages_for(plan: @plan, codespaces: @codespaces)
    strict_validation_errors = JSON::Validator.fully_validate(Codespaces::BillingMessageValidator::JSON_SCHEMA_PATH, message, fragment: @strict_fragment_path)
    permissive_validation_errors = JSON::Validator.fully_validate(Codespaces::BillingMessageValidator::JSON_SCHEMA_PATH, message, fragment: @permissive_fragment_path)
    assert_equal strict_validation_errors.length, 0
    assert_equal permissive_validation_errors.length, 0
  end

end
