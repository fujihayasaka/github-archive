# typed: true
# frozen_string_literal: true

require "test_helper"

class StructuredTemplatesCheckboxTest < GitHub::TestCase
  fixtures do
    @docs_link = StructuredTemplates::ConfigurationBase::DOCS_URL
  end

  context ".valid?" do
    test "true for simple checkbox elements" do
      optional_hash = {
        "id" => "foo",
        "label" => "Example checkbox",
      }

      required_hash = {
        "label" => "Another checkbox",
        "required" => true,
      }

      optional_checkbox = StructuredTemplates::Checkbox.new(input: optional_hash)
      required_checkbox = StructuredTemplates::Checkbox.new(input: required_hash)

      assert_predicate optional_checkbox, :valid?
      assert_predicate required_checkbox, :valid?

      assert_equal "Example checkbox", optional_checkbox.label
      refute optional_checkbox.required
      assert_equal "foo", optional_checkbox.id

      assert_equal "Another checkbox", required_checkbox.label
      assert_equal "5178591e1fb2d7e5f1b47da0a19c4994a37b82a46ad863144901e142824f0383", required_checkbox.id
      assert required_checkbox.required
    end

    test "true for simple checkbox elements with utf8" do
      required_hash = {
        "label" => "测试",
        "required" => true,
      }
      required_checkbox = StructuredTemplates::Checkbox.new(input: required_hash)
      required_checkbox_same = StructuredTemplates::Checkbox.new(input: required_hash)
      assert_predicate required_checkbox, :valid?

      assert_equal "测试", required_checkbox.label
      assert_equal "6aa8f49cc992dfd75a114269ed26de0ad6d4e7d7a70d9c8afb3d7a57a88a73ed", required_checkbox.id
      assert required_checkbox.id.is_a? String
      assert_equal required_checkbox.id, required_checkbox_same.id
      assert required_checkbox.required
    end

    test "false if extraneous attributes provided" do
      extra_attrs = {
        "label" => "Example checkbox",
        "cherry" => "cola",
        "root" => "beer",
      }

      input = StructuredTemplates::Checkbox.new(input: extra_attrs)

      refute_predicate input, :valid?
      assert_equal ["`cherry` is not a permitted attribute", "`root` is not a permitted attribute"], input.errors.full_messages
      assert_equal "#{@docs_link}#bodyi-x-is-not-a-permitted-attribute", input.errors.first.options[:docs]
    end

    test "false if label is not specified" do
      hash = { "required" => true }

      input = StructuredTemplates::Checkbox.new(input: hash)

      refute_predicate input, :valid?
      assert_equal ["Required attribute key `label` is missing"], input.errors.full_messages
      assert_equal "#{@docs_link}#bodyi-required-attribute-key-value-is-missing", input.errors.first.options[:docs]
    end

    test "false for empty hash" do
      input = StructuredTemplates::Checkbox.new(input: {})

      refute_predicate input, :valid?
      assert_equal ["Required attribute key `label` is missing"], input.errors.full_messages
      assert_equal "#{@docs_link}#bodyi-required-attribute-key-value-is-missing", input.errors.first.options[:docs]
    end
  end

  context "type checks" do
    test "errors if label is anything other than a string" do
      input_hash = { "label" => true }

      input = StructuredTemplates::Checkbox.new(input: input_hash)

      refute_predicate input, :valid?
      assert_equal ["`label` must be of type String and cannot be empty"], input.errors.full_messages
      assert_equal "#{@docs_link}#bodyi-label-must-be-a-string", input.errors.first.options[:docs]
    end

    test "errors if id is anything other than a string" do
      input_hash = {
        "id" => true,
        "label" => "foo"
      }

      input = StructuredTemplates::Checkbox.new(input: input_hash)

      refute_predicate input, :valid?
      assert_equal ["`id` must be of type String and cannot be empty"], input.errors.full_messages
      assert_equal "#{@docs_link}#bodyi-label-must-be-a-string", input.errors.first.options[:docs]
    end

    test "errors if required is anything other than a string" do
      input_hash = {
        "label" => "Example checkbox",
        "required" => "hi",
      }

      input = StructuredTemplates::Checkbox.new(input: input_hash)

      refute_predicate input, :valid?
      assert_equal ["`required` must be of type Boolean"], input.errors.full_messages
      assert_equal "#{@docs_link}#bodyi-label-must-be-a-string", input.errors.first.options[:docs]
    end
  end
end
