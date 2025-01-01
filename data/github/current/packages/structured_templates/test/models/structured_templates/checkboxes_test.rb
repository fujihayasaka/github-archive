# typed: true
# frozen_string_literal: true

require "test_helper"

class StructuredTemplatesCheckboxesTest < GitHub::TestCase
  fixtures do
    @docs_link = StructuredTemplates::ConfigurationBase::DOCS_URL
  end

  context ".valid?" do
    test "true for simple checkboxes element" do
      minimal_hash = {
        "type" => "checkboxes",
        "attributes" => {
          "label" => "Test Checkboxes",
          "options" => [
            { "label" => "Example checkbox" },
          ],
        }
      }

      meatier_hash = {
        "type" => "checkboxes",
        "attributes" => {
          "label" => "Test Checkboxes",
          "options" => [
            { "label" => "Example checkbox" },
            {
              "label" => "Another checkbox",
              "required" => true,
            },
          ],
        }
      }

      small_input = StructuredTemplates::Checkboxes.new(input: minimal_hash)
      big_input = StructuredTemplates::Checkboxes.new(input: meatier_hash)

      assert_predicate small_input, :valid?
      assert_equal 1, small_input.checkboxes.count
      assert_predicate big_input, :valid?
      assert_equal 2, big_input.checkboxes.count

      assert_equal "Example checkbox", small_input.checkboxes.first.label
      refute small_input.checkboxes.first.required
      assert_equal "Example checkbox", big_input.checkboxes.first.label
      refute big_input.checkboxes.first.required
      assert_equal "Another checkbox", big_input.checkboxes.second.label
      assert big_input.checkboxes.second.required
    end

    test "false if extraneous attributes provided" do
      extra_attrs = {
        "type" => "checkboxes",
        "attributes" => {
          "label" => "Who is your favorite LOONA member?",
          "cherry" => "cola",
          "root" => "beer",
          "options" => [
            { "label" => "Example checkbox" },
          ],
        }
      }

      input = StructuredTemplates::Checkboxes.new(input: extra_attrs)

      refute_predicate input, :valid?
      assert_equal ["`cherry` is not a permitted attribute", "`root` is not a permitted attribute"], input.errors.full_messages
      assert_equal "#{@docs_link}#bodyi-x-is-not-a-permitted-attribute", input.errors.first.options[:docs]
    end

    test "false if extraneous top-level keys provided" do
      extra_keys = {
        "type" => "checkboxes",
        "extra" => "key",
        "attributes" => {
          "label" => "my Checkboxes",
          "options" => [
            { "label" => "Example checkbox" },
          ],
        }
      }

      input = StructuredTemplates::Checkboxes.new(input: extra_keys)

      refute_predicate input, :valid?
      assert_equal ["`extra` is not a permitted key"], input.errors.full_messages
      assert_equal "#{@docs_link}#bodyi-x-is-not-a-permitted-key", input.errors.first.options[:docs]
    end

    test "false if label for choice is not specified" do
      hash = {
        "type" => "checkboxes",
        "attributes" => {
          "label" => "my Checkboxes",
          "options" => [
            { "required" => true },
          ],
        }
      }

      input = StructuredTemplates::Checkboxes.new(input: hash)

      refute_predicate input, :valid?
      assert_equal 1, input.checkboxes.count
      assert_equal ["options[0]: Required attribute key `label` is missing"], input.errors.full_messages
      assert_equal "#{@docs_link}#bodyi-required-attribute-key-value-is-missing", input.errors.first.options[:docs]
    end

    test "false if options is not specified" do
      input_hash = {
        "type" => "checkboxes",
        "attributes" => {
          "label" => "Stan HaSeul",
        }
      }

      input = StructuredTemplates::Checkboxes.new(input: input_hash)

      refute_predicate input, :valid?
      assert_equal ["Required attribute key `options` is missing"], input.errors.full_messages
      assert_equal "#{@docs_link}#bodyi-required-attribute-key-value-is-missing", input.errors.first.options[:docs]
    end

    test "false if options is an array of strings" do
      input_hash = {
        "type" => "checkboxes",
        "attributes" => {
          "label" => "my Checkboxes",
          "options" => [
            "Example checkbox",
          ],
        }
      }

      input = StructuredTemplates::Checkboxes.new(input: input_hash)

      refute_predicate input, :valid?
      assert_equal ["`options` values must be of type Hash"], input.errors.full_messages
      assert_equal "#{@docs_link}#bodyi-required-attribute-key-value-is-missing", input.errors.first.options[:docs]
    end
  end

  context "type checks" do
    test "errors if label is anything other than a string" do
      input_hash = {
        "type" => "checkboxes",
        "attributes" => {
          "label" => ["yo"],
          "options" => [
            { "label" => "Example checkbox" },
          ],
        }
      }

      input = StructuredTemplates::Checkboxes.new(input: input_hash)

      refute_predicate input, :valid?
      assert_equal ["`label` must be of type String and cannot be empty"], input.errors.full_messages
      assert_equal "#{@docs_link}#bodyi-label-must-be-a-string", input.errors.first.options[:docs]
    end

    test "errors if label is missing" do
      input_hash = {
        "type" => "checkboxes",
        "attributes" => {
          "options" => [
            { "label" => "Example checkbox" },
          ],
        }
      }

      input = StructuredTemplates::Checkboxes.new(input: input_hash)

      refute_predicate input, :valid?
      assert_equal ["Required attribute key `label` is missing"], input.errors.full_messages
      assert_equal "#{@docs_link}#bodyi-required-attribute-key-value-is-missing", input.errors.first.options[:docs]
    end

    test "errors if id is anything other than a string" do
      input_hash = {
        "type" => "checkboxes",
        "id" => 2.1,
        "attributes" => {
          "label" => "Who is your favorite LOONA member?",
          "options" => [
            { "label" => "Example checkbox" },
          ],
        }
      }

      input = StructuredTemplates::Checkboxes.new(input: input_hash)

      refute_predicate input, :valid?
      assert_equal ["`id` must be of type String and cannot be empty"], input.errors.full_messages
      assert_equal "#{@docs_link}#bodyi-label-must-be-a-string", input.errors.first.options[:docs]
    end

    test "errors if description is anything other than a string" do
      input_hash = {
        "type" => "checkboxes",
        "attributes" => {
          "label" => "Who is your favorite LOONA member?",
          "description" => {
            "nested" => "incorrectly"
          },
          "options" => [
            { "label" => "Example checkbox" },
          ],
        }
      }

      input = StructuredTemplates::Checkboxes.new(input: input_hash)

      refute_predicate input, :valid?
      assert_equal ["`description` must be of type String and cannot be empty"], input.errors.full_messages
      assert_equal "#{@docs_link}#bodyi-label-must-be-a-string", input.errors.first.options[:docs]
    end

    test "false if options is anything other than a list" do
      input_hash = {
        "type" => "checkboxes",
        "attributes" => {
          "label" => "Who is your favorite LOONA member?",
          "options" => "Jinsoul",
        }
      }

      input = StructuredTemplates::Checkboxes.new(input: input_hash)

      refute_predicate input, :valid?
      assert_equal ["`options` must be of type Array"], input.errors.full_messages
      assert_equal "#{@docs_link}#bodyi-label-must-be-a-string", input.errors.first.options[:docs]
    end
  end

  context "unique options" do
    test "invalid if duplicate entries in options" do
      input_hash = {
        "type" => "checkboxes",
        "attributes" => {
          "label" => "Who is your favorite LOONA member?",
          "options" => [
            { "label" => "Example checkbox" },
            { "label" => "Example checkbox" },
          ],
        }
      }

      input = StructuredTemplates::Checkboxes.new(input: input_hash)

      refute_predicate input, :valid?
      assert_equal ["`options` must be unique"], input.errors.full_messages
      assert_equal "#{@docs_link}#options-must-be-unique", input.errors.first.options[:docs]
    end
  end
end
