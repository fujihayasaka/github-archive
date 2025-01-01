# typed: true
# frozen_string_literal: true

require "test_helper"

class StructuredTemplatesInputTest < GitHub::TestCase
  fixtures do
    @docs_link = "https://docs.github.com/communities/using-templates-to-encourage-useful-issues-and-pull-requests/common-validation-errors-when-creating-issue-forms"
  end

  context ".valid?" do
    test "true as long as type is correct and has label" do
      minimal_hash = {
        "type" => "input",
        "attributes" => {
          "label" => "Name",
        }
      }
      meatier_hash = {
        "type" => "input",
        "id" => "name",
        "attributes" => {
          "label" => "Name",
          "description" => "Your name",
          "placeholder" => "ex. Alice",
          "value" => "Alice",
        },
        "validations" => {
          "required" => false,
        }
      }

      small_input = StructuredTemplates::Input.new(input: minimal_hash)
      big_input = StructuredTemplates::Input.new(input: meatier_hash)

      assert_predicate small_input, :valid?
      assert_predicate big_input, :valid?

      assert_equal "Name", big_input.label
      assert_equal "Alice", big_input.value
    end

    test "false if extraneous attributes provided" do
      extra_attrs = {
        "type" => "input",
        "attributes" => {
          "label" => "Who is your favorite LOONA member?",
          "cherry" => "cola",
          "root" => "beer"
        }
      }

      input = StructuredTemplates::Input.new(input: extra_attrs)
      refute_predicate input, :valid?
      assert_equal ["`cherry` is not a permitted attribute", "`root` is not a permitted attribute"], input.errors.full_messages
      assert_equal "#{@docs_link}#bodyi-x-is-not-a-permitted-attribute", input.errors.first.options[:docs]
    end

    test "false if extraneous top-level keys provided" do
      extra_keys = {
        "type" => "input",
        "extra" => "key",
        "attributes" => {
          "label" => "some-label"
        }
      }

      input = StructuredTemplates::Input.new(input: extra_keys)
      refute_predicate input, :valid?
      assert_equal ["`extra` is not a permitted key"], input.errors.full_messages
      assert_equal "#{@docs_link}#bodyi-x-is-not-a-permitted-key", input.errors.first.options[:docs]
    end

    test "false if label is not specified" do
      input_hash = {
        "type" => "input",
        "attributes" => {
          "value" => "HaSeul",
        }
      }

      input = StructuredTemplates::Input.new(input: input_hash)

      refute_predicate input, :valid?
      assert_equal ["Required attribute key `label` is missing"], input.errors.full_messages
      assert_equal "#{@docs_link}#bodyi-required-attribute-key-value-is-missing", input.errors.first.options[:docs]
    end

    context "forbidden word checks" do
      test "false if label contains a forbidden word" do
        input_hash = {
          "type" => "input",
          "attributes" => {
            "label" => "Password"
          }
        }

        input = StructuredTemplates::Input.new(input: input_hash)

        refute_predicate input, :valid?
        assert_equal ["Label contains a forbidden word"], input.errors.full_messages
        assert_equal "#{@docs_link}#bodyi-label-contains-forbidden-word", input.errors.first.options[:docs]
      end

      test "false if label contains a string with a forbidden word" do
        input_hash = {
          "type" => "input",
          "attributes" => {
            "label" => "gimme ur pAsSwOrD pretty please"
          }
        }

        input = StructuredTemplates::Input.new(input: input_hash)

        refute_predicate input, :valid?
        assert_equal ["Label contains a forbidden word"], input.errors.full_messages
        assert_equal "#{@docs_link}#bodyi-label-contains-forbidden-word", input.errors.first.options[:docs]
      end

      test "false if label contains a string with a forbidden word and some punctuation" do
        input_hash = {
          "type" => "input",
          "attributes" => {
            "label" => "put ur password!! here pretty please"
          }
        }

        input = StructuredTemplates::Input.new(input: input_hash)

        refute_predicate input, :valid?
        assert_equal ["Label contains a forbidden word"], input.errors.full_messages
        assert_equal "#{@docs_link}#bodyi-label-contains-forbidden-word", input.errors.first.options[:docs]
      end

      test "false if label contains a string with a forbidden phrase" do
        input_hash = {
          "type" => "input",
          "attributes" => {
            "label" => "gimme ur bank account number please"
          }
        }

        input = StructuredTemplates::Input.new(input: input_hash)

        refute_predicate input, :valid?
        assert_equal ["Label contains a forbidden word"], input.errors.full_messages
        assert_equal "#{@docs_link}#bodyi-label-contains-forbidden-word", input.errors.first.options[:docs]
      end
    end

    context "type checks" do
      test "errors if label is anything other than a string" do
        input_hash = {
          "type" => "input",
          "attributes" => {
            "label" => ["yo"]
          }
        }

        input = StructuredTemplates::Input.new(input: input_hash)

        refute_predicate input, :valid?
        assert_equal ["`label` must be of type String and cannot be empty"], input.errors.full_messages
        assert_equal "#{@docs_link}#bodyi-label-must-be-a-string", input.errors.first.options[:docs]
      end

      test "errors if description is anything other than a string" do
        input_hash = {
          "type" => "input",
          "attributes" => {
            "label" => "Who is your favorite LOONA member?",
            "description" => {
              "nested" => "incorrectly"
            }
          }
        }

        input = StructuredTemplates::Input.new(input: input_hash)

        refute_predicate input, :valid?
        assert_equal ["`description` must be of type String and cannot be empty"], input.errors.full_messages
        assert_equal "#{@docs_link}#bodyi-label-must-be-a-string", input.errors.first.options[:docs]
      end

      test "errors if required is anything other than a boolean" do
        input_hash = {
          "type" => "input",
          "attributes" => {
            "label" => "Who is your favorite LOONA member?",
          },
          "validations" => {
            "required" => "sure",
          }
        }

        input = StructuredTemplates::Input.new(input: input_hash)

        refute_predicate input, :valid?
        assert_equal ["`required` must be of type Boolean"], input.errors.full_messages
        assert_equal "#{@docs_link}#bodyi-label-must-be-a-string", input.errors.first.options[:docs]
      end

      test "false if validations is passed improperly" do
        input_hash = {
          "type" => "input",
          "attributes" => {
            "label" => "Who is your favorite LOONA member?",
          },
          "validations" => true
        }

        input = StructuredTemplates::Input.new(input: input_hash)

        refute_predicate input, :valid?
        assert_equal ["`validations` must be of type Hash"], input.errors.full_messages
        assert_equal "#{@docs_link}#bodyi-label-must-be-a-string", input.errors.first.options[:docs]
      end

      test "false if placeholder is anything other than a string" do
        input_hash = {
          "type" => "input",
          "attributes" => {
            "label" => "Who is your favorite LOONA member?",
            "placeholder" => %w[my placeholder text],
          }
        }

        input = StructuredTemplates::Input.new(input: input_hash)
        refute_predicate input, :valid?
        assert_equal ["`placeholder` must be of type String and cannot be empty"], input.errors.full_messages
        assert_equal "#{@docs_link}#bodyi-label-must-be-a-string", input.errors.first.options[:docs]
      end

      test "false if value is anything other than a string" do
        input_hash = {
          "type" => "input",
          "attributes" => {
            "label" => "Who is your favorite LOONA member?",
            "value" => 4,
          }
        }

        input = StructuredTemplates::Input.new(input: input_hash)
        refute_predicate input, :valid?
        assert_equal ["`value` must be of type String and cannot be empty"], input.errors.full_messages
        assert_equal "#{@docs_link}#bodyi-label-must-be-a-string", input.errors.first.options[:docs]
      end

      test "false if id is anything other than a string" do
        input_hash = {
          "type" => "input",
          "id" => false,
          "attributes" => {
            "label" => "Who is your favorite LOONA member?",
          }
        }

        input = StructuredTemplates::Input.new(input: input_hash)
        refute_predicate input, :valid?
        assert_equal ["`id` must be of type String and cannot be empty"], input.errors.full_messages
        assert_equal "#{@docs_link}#bodyi-label-must-be-a-string", input.errors.first.options[:docs]
      end
    end

    context "default values" do
      test "required defaults to false if unsupplied" do
        input_hash = {
          "type" => "input",
          "attributes" => {
            "label" => "Who is your favorite LOONA member?",
          }
        }

        input = StructuredTemplates::Input.new(input: input_hash)
        assert_predicate input, :valid?
        assert_equal false, input.required
      end
    end

    context "#id" do
      test "sets ID if defined" do
        input_hash = {
          "type" => "input",
          "id" => "fav",
          "attributes" => {
            "label" => "Who is your favorite LOONA member?",
          }
        }

        input = StructuredTemplates::Input.new(input: input_hash)
        assert_predicate input, :valid?
        assert_equal "fav", input.id
      end

      test "ID can only be alphanumeric, dashes, and underscores" do
        input_hash = {
          "type" => "input",
          "id" => "fav member?",
          "attributes" => {
            "label" => "Who is your favorite LOONA member?",
          }
        }

        input = StructuredTemplates::Input.new(input: input_hash)
        refute_predicate input, :valid?
        assert_equal ["`id` can contain only numbers, letters, -, _"], input.errors.full_messages
        assert_equal "#{@docs_link}#bodyi-id-can-only-contain-numbers-letters---_", input.errors.first.options[:docs]
      end

      test "computes ID from label if no ID supplied" do
        input_hash = {
          "type" => "input",
          "attributes" => {
            "label" => "Who is your favorite LOONA member?",
          }
        }

        input = StructuredTemplates::Input.new(input: input_hash)
        assert_predicate input, :valid?
        assert_equal "23d9783ca84e490ed1af77b7f8fc11fc02a90b8358da66e62845d563435b31f6", input.id
      end
    end
  end
end
