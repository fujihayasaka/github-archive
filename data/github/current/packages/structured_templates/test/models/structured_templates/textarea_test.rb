# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueFormsTextareaTest < GitHub::TestCase
  fixtures do
    @docs_link = "https://docs.github.com/communities/using-templates-to-encourage-useful-issues-and-pull-requests/common-validation-errors-when-creating-issue-forms"
  end

  context ".valid?" do
    test "true as long as type is correct and has label" do
      minimal_hash = {
        "type" => "textarea",
        "attributes" => {
          "label" => "Hatsune Miku",
        }
      }
      meatier_hash = {
        "type" => "textarea",
        "id" => "nom",
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

      small_input = StructuredTemplates::Textarea.new(input: minimal_hash)
      big_input = StructuredTemplates::Textarea.new(input: meatier_hash)

      assert_predicate small_input, :valid?
      assert_predicate big_input, :valid?

      assert_equal "Name", big_input.label
      assert_equal "Alice", big_input.value
    end

    test "false if extraneous attributes provided" do
      extra_attrs = {
        "type" => "input",
        "attributes" => {
          "label" => "Sodas",
          "cherry" => "cola",
          "root" => "beer",
        }
      }

      input = StructuredTemplates::Textarea.new(input: extra_attrs)
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

      input = StructuredTemplates::Textarea.new(input: extra_keys)
      refute_predicate input, :valid?
      assert_equal ["`extra` is not a permitted key"], input.errors.full_messages
      assert_equal "#{@docs_link}#bodyi-x-is-not-a-permitted-key", input.errors.first.options[:docs]
    end

    test "false if label is not specified" do
      input_hash = {
        "type" => "textarea",
        "attributes" => {
          "description" => "Your name",
          "placeholder" => "ex. Alice",
        }
      }

      input = StructuredTemplates::Textarea.new(input: input_hash)

      refute_predicate input, :valid?
      assert_equal ["Required attribute key `label` is missing"], input.errors.full_messages
      assert_equal "#{@docs_link}#bodyi-required-attribute-key-value-is-missing", input.errors.first.options[:docs]
    end

    context "forbidden word checks" do
      test "false if label contains a forbidden word" do
        input_hash = {
          "type" => "textarea",
          "attributes" => {
            "label" => "Password"
          }
        }

        input = StructuredTemplates::Textarea.new(input: input_hash)

        refute_predicate input, :valid?
        assert_equal ["Label contains a forbidden word"], input.errors.full_messages
        assert_equal "#{@docs_link}#bodyi-label-contains-forbidden-word", input.errors.first.options[:docs]
      end

      test "false if label contains a string with a forbidden word" do
        input_hash = {
          "type" => "textarea",
          "attributes" => {
            "label" => "gimme ur pAsSwOrD pretty please"
          }
        }

        input = StructuredTemplates::Textarea.new(input: input_hash)

        refute_predicate input, :valid?
        assert_equal ["Label contains a forbidden word"], input.errors.full_messages
        assert_equal "#{@docs_link}#bodyi-label-contains-forbidden-word", input.errors.first.options[:docs]
      end

      test "false if label contains a string with a forbidden word and some punctuation" do
        input_hash = {
          "type" => "textarea",
          "attributes" => {
            "label" => "put ur password!! here pretty please"
          }
        }

        input = StructuredTemplates::Textarea.new(input: input_hash)

        refute_predicate input, :valid?
        assert_equal ["Label contains a forbidden word"], input.errors.full_messages
        assert_equal "#{@docs_link}#bodyi-label-contains-forbidden-word", input.errors.first.options[:docs]
      end

      test "false if label contains a string with a forbidden phrase" do
        input_hash = {
          "type" => "textarea",
          "attributes" => {
            "label" => "gimme ur bank account number please"
          }
        }

        input = StructuredTemplates::Textarea.new(input: input_hash)

        refute_predicate input, :valid?
        assert_equal ["Label contains a forbidden word"], input.errors.full_messages
        assert_equal "#{@docs_link}#bodyi-label-contains-forbidden-word", input.errors.first.options[:docs]
      end
    end

    context "type checks" do
      test "errors if label is anything other than a string" do
        input_hash = {
          "type" => "textarea",
          "attributes" => {
            "label" => ["yo"]
          }
        }

        input = StructuredTemplates::Textarea.new(input: input_hash)

        refute_predicate input, :valid?
        assert_equal ["`label` must be of type String and cannot be empty"], input.errors.full_messages
        assert_equal "#{@docs_link}#bodyi-label-must-be-a-string", input.errors.first.options[:docs]
      end

      test "errors if description is anything other than a string" do
        input_hash = {
          "type" => "textarea",
          "attributes" => {
            "label" => "Hatsune Miku",
            "description" => {
              "nested" => "incorrectly"
            }
          }
        }

        input = StructuredTemplates::Textarea.new(input: input_hash)

        refute_predicate input, :valid?
        assert_equal ["`description` must be of type String and cannot be empty"], input.errors.full_messages
        assert_equal "#{@docs_link}#bodyi-label-must-be-a-string", input.errors.first.options[:docs]
      end

      test "errors if required is anything other than a boolean" do
        input_hash = {
          "type" => "textarea",
          "attributes" => {
            "label" => "Hatsune Miku",
          },
          "validations" => {
            "required" => "sure"
          }
        }

        input = StructuredTemplates::Textarea.new(input: input_hash)

        refute_predicate input, :valid?
        assert_equal ["`required` must be of type Boolean"], input.errors.full_messages
        assert_equal "#{@docs_link}#bodyi-label-must-be-a-string", input.errors.first.options[:docs]
      end

      test "errors if validations is anything other than a hash" do
        input_hash = {
          "type" => "textarea",
          "attributes" => {
            "label" => "Hatsune Miku",
          },
          "validations" => 1
        }

        input = StructuredTemplates::Textarea.new(input: input_hash)

        refute_predicate input, :valid?
        assert_equal ["`validations` must be of type Hash"], input.errors.full_messages
        assert_equal "#{@docs_link}#bodyi-label-must-be-a-string", input.errors.first.options[:docs]
      end

      test "false if placeholder is anything other than a string" do
        input_hash = {
          "type" => "textarea",
          "attributes" => {
            "label" => "Hatsune Miku",
            "placeholder" => %w[my placeholder text],
          }
        }

        input = StructuredTemplates::Textarea.new(input: input_hash)
        refute_predicate input, :valid?
        assert_equal ["`placeholder` must be of type String and cannot be empty"], input.errors.full_messages
        assert_equal "#{@docs_link}#bodyi-label-must-be-a-string", input.errors.first.options[:docs]
      end

      test "false if value is anything other than a string" do
        input_hash = {
          "type" => "textarea",
          "attributes" => {
            "label" => "Hatsune Miku",
            "value" => 4,
          }
        }

        input = StructuredTemplates::Textarea.new(input: input_hash)
        refute_predicate input, :valid?
        assert_equal ["`value` must be of type String and cannot be empty"], input.errors.full_messages
        assert_equal "#{@docs_link}#bodyi-label-must-be-a-string", input.errors.first.options[:docs]
      end

      test "false if id is anything other than a string" do
        input_hash = {
          "type" => "textarea",
          "id" => 34,
          "attributes" => {
            "label" => "Who is your favorite LOONA member?",
          }
        }

        input = StructuredTemplates::Textarea.new(input: input_hash)
        refute_predicate input, :valid?
        assert_equal ["`id` must be of type String and cannot be empty"], input.errors.full_messages
        assert_equal "#{@docs_link}#bodyi-label-must-be-a-string", input.errors.first.options[:docs]
      end
    end

    context "default values" do
      test "required defaults to false if unsupplied" do
        input_hash = {
          "type" => "textarea",
          "attributes" => {
            "label" => "Hatsune Miku",
          }
        }

        input = StructuredTemplates::Textarea.new(input: input_hash)
        assert_predicate input, :valid?
        assert_equal false, input.required
      end
    end
  end

  context ".codeblock?" do
    test "true if render key is present" do
      input_hash = {
        "type" => "textarea",
        "attributes" => {
          "label" => "Who is your favorite LOONA member?",
          "render" => "yaml",
        }
      }

      input = StructuredTemplates::Textarea.new(input: input_hash)
      assert_predicate input, :codeblock?
    end

    test "false if render set to nil" do
      input_hash = {
        "type" => "textarea",
        "attributes" => {
          "label" => "Who is your favorite LOONA member?",
          "render" => nil,
        }
      }

      input = StructuredTemplates::Textarea.new(input: input_hash)
      refute_predicate input, :codeblock?
    end

    test "false if render undefined" do
      input_hash = {
        "type" => "textarea",
        "attributes" => {
          "label" => "Who is your favorite LOONA member?",
        }
      }

      input = StructuredTemplates::Textarea.new(input: input_hash)
      refute_predicate input, :codeblock?
    end
  end

  context "#id" do
    test "sets ID if defined" do
      input_hash = {
        "type" => "textarea",
        "id" => "fav",
        "attributes" => {
          "label" => "Who is your favorite LOONA member?",
        }
      }

      input = StructuredTemplates::Textarea.new(input: input_hash)
      assert_equal "fav", input.id
    end

    test "returns parameterized label name if id not defined" do
      input_hash = {
        "type" => "textarea",
        "attributes" => {
          "label" => "Hatsune Miku",
        }
      }

      input = StructuredTemplates::Textarea.new(input: input_hash)
      assert_equal "4fc2d17a36a087dc7b3df2b4d214c1f704f3b24fbe6417cdeaaf8b5d864700e5", input.id
    end

    test "returns nil if label is not a string" do
      input_hash = {
        "type" => "textarea",
        "attributes" => {
          "label" => 4,
        }
      }

      input = StructuredTemplates::Textarea.new(input: input_hash)
      assert_nil input.id
    end

    test "returns nil if label is missing" do
      input_hash = {
        "type" => "textarea",
        "attributes" => {},
      }

      input = StructuredTemplates::Textarea.new(input: input_hash)
      assert_nil input.id
    end
  end
end
