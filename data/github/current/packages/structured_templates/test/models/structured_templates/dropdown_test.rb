# typed: true
# frozen_string_literal: true

require "test_helper"

class StructuredTemplatesDropdownTest < GitHub::TestCase
  fixtures do
    @docs_link = "https://docs.github.com/communities/using-templates-to-encourage-useful-issues-and-pull-requests/common-validation-errors-when-creating-issue-forms"
  end

  context ".valid?" do
    test "true as long as type is correct, has a label, and a options list" do
      minimal_hash = {
        "type" => "dropdown",
        "attributes" => {
          "label" => "People",
          "options" => %w[Diana Rita Vivian],
        }
      }
      meatier_hash = {
        "type" => "dropdown",
        "id" => "peeps",
        "attributes" => {
          "label" => "People",
          "options" => %w[Diana Rita Vivian],
          "description" => "Please select a hero",
        },
        "validations" => {
          "required" => true,
        }
      }

      small_input = StructuredTemplates::Dropdown.new(input: minimal_hash)
      big_input = StructuredTemplates::Dropdown.new(input: meatier_hash)

      assert_predicate small_input, :valid?
      assert_predicate big_input, :valid?

      assert_equal "People", big_input.label
      assert_equal "peeps", big_input.id
      assert_equal "Please select a hero", big_input.description
      assert_equal %w[Diana Rita Vivian], big_input.options
    end

    test "false if extraneous attributes provided" do
      extra_attrs = {
        "type" => "dropdown",
        "attributes" => {
          "label" => "Who is your favorite LOONA member?",
          "cherry" => "cola",
          "root" => "beer",
          "options" => %w[this that],
        }
      }

      input = StructuredTemplates::Dropdown.new(input: extra_attrs)

      refute_predicate input, :valid?
      assert_equal ["`cherry` is not a permitted attribute", "`root` is not a permitted attribute"], input.errors.full_messages
      assert_equal "#{@docs_link}#bodyi-x-is-not-a-permitted-attribute", input.errors.first.options[:docs]
    end

    test "false if extraneous top-level keys provided" do
      extra_keys = {
        "type" => "dropdown",
        "extra" => "key",
        "attributes" => {
          "label" => "some-label",
          "options" => %w[this that],
        }
      }

      input = StructuredTemplates::Dropdown.new(input: extra_keys)

      refute_predicate input, :valid?
      assert_equal ["`extra` is not a permitted key"], input.errors.full_messages
      assert_equal "#{@docs_link}#bodyi-x-is-not-a-permitted-key", input.errors.first.options[:docs]
    end

    test "false if label is not specified" do
      input_hash = {
        "type" => "dropdown",
        "attributes" => {
          "description" => "HaSeul",
          "options" => %w[this that],
        }
      }

      input = StructuredTemplates::Dropdown.new(input: input_hash)

      refute_predicate input, :valid?
      assert_equal ["Required attribute key `label` is missing"], input.errors.full_messages
      assert_equal "#{@docs_link}#bodyi-required-attribute-key-value-is-missing", input.errors.first.options[:docs]
    end

    test "false for non-unique dropdown options" do
      input_hash = {
        "type" => "dropdown",
        "attributes" => {
          "label" => "ready set go",
          "options" => ["duck", "Duck", "GOOSE!", "None"],
        }
      }

      input = StructuredTemplates::Dropdown.new(input: input_hash)

      refute_predicate input, :valid?
      assert_equal ["`options` must be unique", "`options` must not include the reserved word, 'None'"], input.errors.full_messages
    end

    test "unique validation can handle non-string types" do
      input_hash = {
        "type" => "dropdown",
        "attributes" => {
          "label" => "ready set go",
          "options" => ["duck", "true", 200],
        }
      }

      input = StructuredTemplates::Dropdown.new(input: input_hash)

      assert_predicate input, :valid?
    end

    test "booleans are not allowed as dropdown input" do
      input_hash = {
        "type" => "dropdown",
        "attributes" => {
          "label" => "ready set go",
          "options" => ["foo", true],
        }
      }

      input = StructuredTemplates::Dropdown.new(input: input_hash)

      refute_predicate input, :valid?
      assert_equal ["`options` must not include booleans. Please wrap values such as 'yes', and 'true' in quotes"], input.errors.full_messages
    end

    context "type checks" do
      test "errors if label is anything other than a string" do
        input_hash = {
          "type" => "dropdown",
          "attributes" => {
            "label" => ["yo"],
            "options" => %w[this that],
          }
        }

        input = StructuredTemplates::Dropdown.new(input: input_hash)

        refute_predicate input, :valid?
        assert_equal ["`label` must be of type String and cannot be empty"], input.errors.full_messages
        assert_equal "#{@docs_link}#bodyi-label-must-be-a-string", input.errors.first.options[:docs]
      end

      test "errors if id is supplied and anything other than a string" do
        input_hash = {
          "type" => "dropdown",
          "id" => 3,
          "attributes" => {
            "label" => "yo",
            "options" => %w[this that],
          }
        }

        input = StructuredTemplates::Dropdown.new(input: input_hash)

        refute_predicate input, :valid?
        assert_equal ["`id` must be of type String and cannot be empty"], input.errors.full_messages
        assert_equal "#{@docs_link}#bodyi-label-must-be-a-string", input.errors.first.options[:docs]
      end

      test "errors if description is anything other than a string" do
        input_hash = {
          "type" => "dropdown",
          "attributes" => {
            "label" => "Who is your favorite LOONA member?",
            "description" => {
              "nested" => "incorrectly"
            },
            "options" => %w[this that],
          }
        }

        input = StructuredTemplates::Dropdown.new(input: input_hash)

        refute_predicate input, :valid?
        assert_equal ["`description` must be of type String and cannot be empty"], input.errors.full_messages
        assert_equal "#{@docs_link}#bodyi-label-must-be-a-string", input.errors.first.options[:docs]
      end

      test "errors if required is anything other than a boolean" do
        input_hash = {
          "type" => "dropdown",
          "attributes" => {
            "label" => "Who is your favorite LOONA member?",
            "options" => %w[this that],
          },
          "validations" => {
            "required" => "sure",
          }
        }

        input = StructuredTemplates::Dropdown.new(input: input_hash)

        refute_predicate input, :valid?
        assert_equal ["`required` must be of type Boolean"], input.errors.full_messages
        assert_equal "#{@docs_link}#bodyi-label-must-be-a-string", input.errors.first.options[:docs]
      end

      test "errors if validations is anything other than a hash" do
        input_hash = {
          "type" => "dropdown",
          "attributes" => {
            "label" => "Who is your favorite LOONA member?",
            "options" => %w[this that],
          },
          "validations" => false
        }

        input = StructuredTemplates::Dropdown.new(input: input_hash)

        refute_predicate input, :valid?
        assert_equal ["`validations` must be of type Hash"], input.errors.full_messages
        assert_equal "#{@docs_link}#bodyi-label-must-be-a-string", input.errors.first.options[:docs]
      end

      test "false if options is anything other than a list" do
        input_hash = {
          "type" => "dropdown",
          "attributes" => {
            "label" => "Who is your favorite LOONA member?",
            "options" => "Bruce",
          }
        }

        input = StructuredTemplates::Dropdown.new(input: input_hash)

        refute_predicate input, :valid?
        assert_equal ["`options` must be of type Array"], input.errors.full_messages
        assert_equal "#{@docs_link}#bodyi-label-must-be-a-string", input.errors.first.options[:docs]
      end
    end

    context "default values" do
      test "required defaults to false if unsupplied" do
        input_hash = {
          "type" => "dropdown",
          "attributes" => {
            "label" => "Who is your favorite LOONA member?",
            "options" => ["Peter", "Not Peter"]
          }
        }

        input = StructuredTemplates::Dropdown.new(input: input_hash)

        assert_predicate input, :valid?
        assert_equal false, input.required
      end
    end
  end

  context "multiSelect" do
    context ".valid?" do
      test "true as long as type is correct, has a label, and a options list" do
        minimal_hash = {
          "type" => "dropdown",
          "attributes" => {
            "label" => "Versions",
            "multiple" => true,
            "options" => ["Version 1", "Version 2", "Version 3"],
          }
        }
        meatier_hash = {
          "type" => "dropdown",
          "attributes" => {
            "label" => "Versions",
            "multiple" => true,
            "options" => ["Version 1", "Version 2", "Version 3"],
            "description" => "Please select the versions that you like",
          },
          "validations" => {
            "required" => true,
          }
        }

        small_input = StructuredTemplates::Dropdown.new(input: minimal_hash)
        big_input = StructuredTemplates::Dropdown.new(input: meatier_hash)

        assert_predicate small_input, :valid?
        assert_predicate big_input, :valid?

        assert_equal "Versions", big_input.label
        assert_equal "Please select the versions that you like", big_input.description
        assert_equal ["Version 1", "Version 2", "Version 3"], big_input.options
      end

      test "false if extraneous attributes provided" do
        extra_attrs = {
          "type" => "dropdown",
          "attributes" => {
            "label" => "Versions",
            "multiple" => true,
            "options" => ["Version 1", "Version 2", "Version 3"],
            "cherry" => "cola",
            "root" => "beer",
          }
        }

        input = StructuredTemplates::Dropdown.new(input: extra_attrs)

        refute_predicate input, :valid?
        assert_equal ["`cherry` is not a permitted attribute", "`root` is not a permitted attribute"], input.errors.full_messages
        assert_equal "#{@docs_link}#bodyi-x-is-not-a-permitted-attribute", input.errors.first.options[:docs]
      end

      test "false if extraneous top-level keys provided" do
        extra_keys = {
          "type" => "dropdown",
          "extra" => "key",
          "attributes" => {
            "label" => "Versions",
            "multiple" => true,
            "options" => ["Version 1", "Version 2", "Version 3"],
          }
        }

        input = StructuredTemplates::Dropdown.new(input: extra_keys)

        refute_predicate input, :valid?
        assert_equal ["`extra` is not a permitted key"], input.errors.full_messages
        assert_equal "#{@docs_link}#bodyi-x-is-not-a-permitted-key", input.errors.first.options[:docs]
      end

      test "false if label is not specified" do
        input_hash = {
          "type" => "dropdown",
          "attributes" => {
            "options" => ["Version 1", "Version 2", "Version 3"],
            "multiple" => true,
            "description" => "Please select the versions that you like",
          }
        }

        input = StructuredTemplates::Dropdown.new(input: input_hash)

        refute_predicate input, :valid?
        assert_equal ["Required attribute key `label` is missing"], input.errors.full_messages
        assert_equal "#{@docs_link}#bodyi-required-attribute-key-value-is-missing", input.errors.first.options[:docs]
      end

      test "false for non-unique dropdown options" do
        input_hash = {
          "type" => "dropdown",
          "attributes" => {
            "label" => "ready set go",
            "multiple" => true,
            "options" => ["duck", "duck", "GOOSE!", "None"],
          }
        }

        input = StructuredTemplates::Dropdown.new(input: input_hash)

        refute_predicate input, :valid?
        assert_equal ["`options` must be unique", "`options` must not include the reserved word, 'None'"], input.errors.full_messages
        assert_equal ["#{@docs_link}#bodyi-options-must-be-unique", "#{@docs_link}#bodyi-options-must-not-include-the-reserved-word-none"],
                     input.errors.map { |error| error.options[:docs] }
      end

      test "booleans are not allowed as dropdown input" do
        input_hash = {
          "type" => "dropdown",
          "attributes" => {
            "label" => "ready set go",
            "multiple" => true,
            "options" => ["foo", true],
          }
        }

        input = StructuredTemplates::Dropdown.new(input: input_hash)

        refute_predicate input, :valid?
        assert_equal ["`options` must not include booleans. Please wrap values such as 'yes', and 'true' in quotes"], input.errors.full_messages
        assert_equal "#{@docs_link}#bodyi-options-must-not-include-booleans-please-wrap-values-such-as-yes-and-true-in-quotes", input.errors.first.options[:docs]
      end

      context "type checks" do
        test "errors if label is anything other than a string" do
          input_hash = {
            "type" => "dropdown",
            "attributes" => {
              "label" => ["yo"],
              "multiple" => true,
              "options" => %w[this that],
            }
          }

          input = StructuredTemplates::Dropdown.new(input: input_hash)

          refute_predicate input, :valid?
          assert_equal ["`label` must be of type String and cannot be empty"], input.errors.full_messages
          assert_equal "#{@docs_link}#bodyi-label-must-be-a-string", input.errors.first.options[:docs]
        end

        test "errors if description is anything other than a string" do
          input_hash = {
            "type" => "dropdown",
            "attributes" => {
              "label" => "Who are your favorite LOONA members?",
              "multiple" => true,
              "description" => {
                "nested" => "incorrectly"
              },
              "options" => %w[this that],
            }
          }

          input = StructuredTemplates::Dropdown.new(input: input_hash)

          refute_predicate input, :valid?
          assert_equal ["`description` must be of type String and cannot be empty"], input.errors.full_messages
          assert_equal "#{@docs_link}#bodyi-label-must-be-a-string", input.errors.first.options[:docs]
        end

        test "errors if required is anything other than a boolean" do
          input_hash = {
            "type" => "dropdown",
            "attributes" => {
              "label" => "Who are your favorite LOONA members?",
              "multiple" => true,
              "options" => %w[this that],
            },
            "validations" => {
              "required" => "sure",
            }
          }

          input = StructuredTemplates::Dropdown.new(input: input_hash)

          refute_predicate input, :valid?
          assert_equal ["`required` must be of type Boolean"], input.errors.full_messages
          assert_equal "#{@docs_link}#bodyi-label-must-be-a-string", input.errors.first.options[:docs]
        end

        test "false if options is anything other than a list" do
          input_hash = {
            "type" => "dropdown",
            "attributes" => {
              "label" => "Who are your favorite LOONA members?",
              "multiple" => true,
              "options" => "Bruce",
            }
          }

          input = StructuredTemplates::Dropdown.new(input: input_hash)

          refute_predicate input, :valid?
          assert_equal ["`options` must be of type Array"], input.errors.full_messages
          assert_equal "#{@docs_link}#bodyi-label-must-be-a-string", input.errors.first.options[:docs]
        end
      end

      context "default values" do
        test "required defaults to false if unsupplied" do
          input_hash = {
            "type" => "dropdown",
            "attributes" => {
              "label" => "Who are your favorite LOONA members?",
              "multiple" => true,
              "options" => ["Peter", "Not Peter"]
            }
          }

          input = StructuredTemplates::Dropdown.new(input: input_hash)

          assert_predicate input, :valid?
          assert_equal false, input.required
        end

        test "if default option is supplied returns index of default option" do
          input_hash = {
            "type" => "dropdown",
            "attributes" => {
              "label" => "Who are your favorite LOONA members?",
              "options" => ["Peter", "Not Peter"],
              "default" => 1
            }
          }

          input = StructuredTemplates::Dropdown.new(input: input_hash)

          assert_predicate input, :valid?
          assert_equal 1, input.default
        end

        test "returns error if default option smaller than 0" do
          input_hash = {
            "type" => "dropdown",
            "attributes" => {
              "label" => "Who are your favorite LOONA members?",
              "options" => ["Peter", "Not Peter"],
              "default" => -1
            }
          }

          input = StructuredTemplates::Dropdown.new(input: input_hash)

          refute_predicate input, :valid?
          assert_equal ["`default` index must be 0 or greater"], input.errors.full_messages
        end

        test "returns error if default option larger than array size" do
          input_hash = {
            "type" => "dropdown",
            "attributes" => {
              "label" => "Who are your favorite LOONA members?",
              "options" => ["Peter", "Not Peter"],
              "default" => 2
            }
          }

          input = StructuredTemplates::Dropdown.new(input: input_hash)

          refute_predicate input, :valid?
          assert_equal ["`default` index is larger that number of options"], input.errors.full_messages
        end
      end
    end
  end
end
