# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionFormsTemplateConfigTest < GitHub::TestCase
  fixtures do
    @docs_link = StructuredTemplates::ConfigurationBase::DOCS_URL
  end

  context "#valid?" do
    context "parsing basic YAML" do
      test "reads a valid YAML string and returns template name and description as attributes" do
        raw_data = <<~YAML
        ---
        body:
        - type: input
          attributes:
            label: "what is your bug?"
        YAML

        config = DiscussionForms::TemplateConfig.new(input: raw_data, path: "some/path").load

        assert_predicate config, :valid?
        input = config.user_inputs.first
        assert_equal "input", input.type
        assert_equal "what is your bug?", input.label
      end

      test "returns an error if loading a file with unparsable YAML contents" do
        raw_data = "unparsable: invalid: yaml"

        config = DiscussionForms::TemplateConfig.new(input: raw_data, path: "some/path").load
        refute_predicate config, :valid?
        assert_equal ["YAML syntax error: (<unknown>): mapping values are not allowed in this context at line 1 column 20"],
                     config.errors.full_messages # error from Psych library
        assert_equal @docs_link, config.errors.first.options[:docs]
      end

      test "returns an error if config is a plain string" do
        raw_data = <<~YAML
        this is a random string
        YAML

        config = DiscussionForms::TemplateConfig.new(input: raw_data, path: nil).load

        refute_predicate config, :valid?
        assert_equal ["Config must contain at least one key"], config.errors.full_messages
      end

      test "returns error if no input is provided" do
        config = DiscussionForms::TemplateConfig.new(input: nil, path: "some/bad_path.yml/a.a").load

        refute_predicate config, :valid?
        assert_equal ["No valid config found in path"], config.errors.full_messages
      end
    end

    context "top-level keys" do
      test "returns error with docs link if contains no keys" do
        raw_data = <<~YAML
        ---
        YAML

        config = DiscussionForms::TemplateConfig.new(input: raw_data, path: "some/path").load
        refute_predicate config, :valid?
        assert_equal ["Config must contain at least one key"], config.errors.full_messages
        assert_equal @docs_link, config.errors.first.options[:docs]
      end

      test "returns error with docs link when top level keys cannot be parsed" do
        raw_data = <<~YAML
        ---
        no-name: Bug Report
        markdown: This template is WRONG!!!!!!!!!
        no: more
        body:
        - type: input
          attributes:
            label: "what is your bug?"
        YAML

        config = DiscussionForms::TemplateConfig.new(input: raw_data, path: "some/path").load
        refute_predicate config, :valid?
        assert_equal ["Config contains reserved YAML keywords as keys"], config.errors.full_messages
        assert_equal "#{@docs_link}#input-is-not-a-permitted-key", config.errors.first.options[:docs]
      end

      test "an empty space does not count as valid for required keys" do
        raw_data = <<~YAML
        ---
        body:
        - type: dropdown
          attributes:
            label: " "
            description: |
              If this is *also* a documentation request, etc, please select that below.
            multiple: true
            options:
            - "/kind documentation"
            - "/kind regression"
            - "/kind deprecation"
            - "/kind cleanup"
        YAML

        config = DiscussionForms::TemplateConfig.new(input: raw_data, path: "some/path").load
        refute_predicate config, :valid?
        assert_equal ["body[0]: `label` must be of type String and cannot be empty"], config.errors.full_messages
        assert_equal "#{@docs_link}#bodyi-label-must-be-a-string", config.errors.first.options[:docs]
      end

      test "does not 500 for checkbox instead of checkboxes" do
        raw_data = <<~YAML
        ---
        body:
        - type: checkbox
          attributes:
            label: Code of Conduct
            description: By submitting this issue, you agree to follow our [Code of Conduct](https://example.com)
            options:
            - label: I agree to follow this project's Code of Conduct
              required: true
        YAML

        config = DiscussionForms::TemplateConfig.new(input: raw_data, path: "some/path").load
        refute_predicate config, :valid?
        assert_equal ["body[0]: `checkbox` is not a valid input type"], config.errors.full_messages
      end

      context "type checks" do
        test "returns error if title is supplied as anything other than a boolean" do
          raw_data = <<~YAML
          ---
          title: ["best", "titles", "ever"]
          body:
          - type: input
            attributes:
              label: "what is your bug?"
          YAML

          config = DiscussionForms::TemplateConfig.new(input: raw_data, path: "some/path").load
          refute_predicate config, :valid?
          assert_equal ["`title` must be of type String and cannot be empty"], config.errors.full_messages
          assert_equal "#{@docs_link}#key-must-be-a-string", config.errors.first.options[:docs]
        end

        test "returns error if labels is supplied as anything other than a string or array of strings" do
          raw_data = <<~YAML
          ---
          labels: true
          body:
          - type: input
            attributes:
              label: "what is your bug?"
          YAML

          config = DiscussionForms::TemplateConfig.new(input: raw_data, path: "some/path").load
          refute_predicate config, :valid?
          assert_equal ["`labels` must be of type String or Array"], config.errors.full_messages
          assert_equal "#{@docs_link}#key-must-be-a-string", config.errors.first.options[:docs]
        end

        test "accepts an array of strings for labels" do
          raw_data = <<~YAML
          ---
          labels:
          - bug
          - wont-fix
          - dont-bother
          body:
          - type: input
            attributes:
              label: "what is your bug?"
          YAML

          config = DiscussionForms::TemplateConfig.new(input: raw_data, path: "some/path").load
          assert_predicate config, :valid?
          assert_equal config.labels, %w[bug wont-fix dont-bother]
        end

        test "returns error if body is supplied as anything other than a string" do
          raw_data = <<~YAML
          ---
          body: I'm an input!!
          YAML

          config = DiscussionForms::TemplateConfig.new(input: raw_data, path: "some/path").load
          refute config.valid?
          assert_equal ["`body` must be of type Array"], config.errors.full_messages
          assert_equal "#{@docs_link}#key-must-be-a-string", config.errors.first.options[:docs]
        end

        test "returns comma-delimited string of errors in the event of multiple validation failures" do
          raw_data = <<~YAML
          ---
          title: 3
          labels:
            Lexis: Plant
          body:
          - type: input
            attributes:
              label: "what is your bug?"
          YAML

          config = DiscussionForms::TemplateConfig.new(input: raw_data, path: "some/path").load
          refute_predicate config, :valid?
          assert_equal ["`title` must be of type String and cannot be empty", "`labels` must be of type String or Array"], config.errors.full_messages
        end
      end

      test "returns error if body is empty" do
        raw_data = <<~YAML
        ---
        body: []
        YAML

        config = DiscussionForms::TemplateConfig.new(input: raw_data, path: "some/path").load
        refute_predicate config, :valid?
        assert_equal ["Body cannot be empty"], config.errors.full_messages
        assert_equal "#{@docs_link}#body-cannot-be-empty-when-issue_body-is-false", config.errors.first.options[:docs]
      end

      test "returns error if body only has nil elements" do
        raw_data = <<~YAML
        ---
        body:
        -
        YAML

        config = DiscussionForms::TemplateConfig.new(input: raw_data, path: "some/path").load
        refute_predicate config, :valid?
        assert_equal ["Body cannot be empty"], config.errors.full_messages
        assert_equal "#{@docs_link}#body-cannot-be-empty-when-issue_body-is-false", config.errors.first.options[:docs]
      end

      test "returns error if body has malformed elements" do
        raw_data = <<~YAML
        ---
        body:
        - A string
        - []
        YAML

        config = DiscussionForms::TemplateConfig.new(input: raw_data, path: "some/path").load
        refute_predicate config, :valid?
        assert_equal ["Template body[0]: Invalid template syntax", "Template body[1]: Invalid template syntax"], config.errors.full_messages
      end

      test "returns error if body contains only `markdown` fields" do
        raw_data = <<~YAML
        ---
        body:
        - type: markdown
          attributes:
            value: The best bugs are the ones left unreported <3
        YAML

        config = DiscussionForms::TemplateConfig.new(input: raw_data, path: "some/path").load
        refute_predicate config, :valid?
        assert_equal ["Body must contain at least one non-markdown field"], config.errors.full_messages
        assert_equal "#{@docs_link}#body-must-contain-at-least-one-non-markdown-field", config.errors.first.options[:docs]
      end
    end

    context "input types" do
      test "template is valid when provided body has a valid type and required attributes" do
        raw_data = <<~YAML
        ---
        body:
        - type: markdown
          attributes:
            value: "we love bugs"
        - type: input
          attributes:
            label: "what is your bug?"
        YAML

        config = DiscussionForms::TemplateConfig.new(input: raw_data, path: "some/path").load
        assert_predicate config, :valid?
        assert_equal "StructuredTemplates::Markdown", config.body.first.class.name
        assert_equal "markdown", config.body.first.type
        assert_equal "we love bugs", config.body.first.value
      end

      test "template is valid when having nested checkboxes attributes" do
        raw_data = <<~YAML
        body:
        - type: checkboxes
          attributes:
            label: What kinds of cats do you like?
            description: You may select more than one.
            options:
              - label: Orange cat (required. Everyone likes orange cats.)
                required: true
              - label: Black cat
        YAML

        config = DiscussionForms::TemplateConfig.new(input: raw_data, path: nil).load
        assert_predicate config, :valid?
      end

      test "returns bubbled-up errors for nested checkboxes attributes" do
        raw_data = <<~YAML
        body:
        - type: checkboxes
          attributes:
            label: What kinds of cats do you like?
            description: You may select more than one.
            options:
              - label: Orange cat (required. Everyone likes orange cats.)
                required: true
              - label: true
        YAML

        config = DiscussionForms::TemplateConfig.new(input: raw_data, path: nil).load
        refute_predicate config, :valid?
        assert_equal ["body[0]: options[1]: `label` must be of type String and cannot be empty"], config.errors.full_messages
        assert_equal "#{@docs_link}#bodyi-label-must-be-a-string", config.errors.first.options[:docs]
      end

      test "returns bubbled-up error if a nested checkbox label is duplicate" do
        raw_data = <<~YAML
        body:
        - type: checkboxes
          attributes:
            label: Who are your favorite Valorant agents?
            description: You may select more than one.
            options:
              - label: Sage
              - label: Killjoy
              - label: Reyna
              - label: Sage
        YAML

        config = DiscussionForms::TemplateConfig.new(input: raw_data, path: nil).load
        refute_predicate config, :valid?
        assert_equal ["body[0]: `options` must be unique"], config.errors.full_messages
        assert_equal "#{@docs_link}#options-must-be-unique", config.errors.first.options[:docs]
      end

      test "returns error if any input `type` keys are missing" do
        raw_data = <<~YAML
        ---
        body:
        - no-type: description
        YAML

        config = DiscussionForms::TemplateConfig.new(input: raw_data, path: "some/path").load
        refute_predicate config, :valid?
        assert_equal ["body[0]: Required key `type` is missing"], config.errors.full_messages
        assert_equal "#{@docs_link}#bodyi-required-key-type-is-missing", config.errors.first.options[:docs]
      end

      test "returns error if any input `attributes` keys is a string" do
        raw_data = <<~YAML
        ---
        body:
        - type: markdown
          attributes: string here
        YAML

        config = DiscussionForms::TemplateConfig.new(input: raw_data, path: "some/path").load
        refute_predicate config, :valid?
        assert_equal ["body[0]: Required attribute key `value` is missing"], config.errors.full_messages
        assert_equal "#{@docs_link}#bodyi-required-attribute-key-value-is-missing", config.errors.first.options[:docs]
      end

      test "returns error if any input `type` keys are outside permitted set of types" do
        raw_data = <<~YAML
        ---
        body:
        - type: party
        YAML

        config = DiscussionForms::TemplateConfig.new(input: raw_data, path: "some/path").load
        refute_predicate config, :valid?
        assert_equal ["body[0]: `party` is not a valid input type"], config.errors.full_messages
        assert_equal "#{@docs_link}#bodyi-x-is-not-a-valid-input-type", config.errors.first.options[:docs]
      end

      test "returns error if any extra top-level keys" do
        raw_data = <<~YAML
        ---
        party: time
        body:
        - type: markdown
          attributes:
            value: "here is a description"
        - type: input
          attributes:
            label: "what is your bug?"
        YAML

        config = DiscussionForms::TemplateConfig.new(input: raw_data, path: "some/path").load
        refute_predicate config, :valid?
        assert_equal ["`party` is not a permitted key"], config.errors.full_messages
        assert_equal "#{@docs_link}#input-is-not-a-permitted-key", config.errors.first.options[:docs]
      end


      context "ID and label validations" do
        context "when all elements have user-supplied ID, ID checking takes precedence" do
          test "the same id with different labels is invalid, and no further label-related validation happens" do
            raw_data = <<~YAML
            ---
            body:
            - type: textarea
              id: dogs
              attributes:
                label: fluffy puppy
            - type: textarea
              id: dogs
              attributes:
                label: woof woof woof!
            YAML

            config = DiscussionForms::TemplateConfig.new(input: raw_data, path: "some/path").load
            refute_predicate config, :valid?
            assert_equal ["Body must have unique `id`s"], config.errors.full_messages
          end

          test "two elements with the same label and same ID is invalid" do
            raw_data = <<~YAML
            ---
            body:
            - type: textarea
              id: dogs
              attributes:
                label: fluffy puppy
            - type: textarea
              id: dogs
              attributes:
                label: fluffy puppy
            YAML

            config = DiscussionForms::TemplateConfig.new(input: raw_data, path: "some/path").load
            refute_predicate config, :valid?
            assert_equal ["Body must have unique `id`s"], config.errors.full_messages
          end

          test "duplicate invalid IDs should generate distinct error messages, and a uniqueness error" do
            raw_data = <<~YAML
            ---
            body:
            - type: textarea
              id: dogs?
              attributes:
                label: fluffy puppy
            - type: textarea
              id: dogs?
              attributes:
                label: woof woof woof!
            YAML

            config = DiscussionForms::TemplateConfig.new(input: raw_data, path: "some/path").load
            refute_predicate config, :valid?
            assert_equal [
                           "body[0]: `id` can contain only numbers, letters, -, _",
                           "body[1]: `id` can contain only numbers, letters, -, _",
                           "Body must have unique `id`s",
                         ], config.errors.full_messages
          end

          test "multiple elements can have the same label if they have different IDs" do
            raw_data = <<~YAML
            ---
            body:
            - type: textarea
              id: dogs
              attributes:
                label: fluffy
                value: woof woof
            - type: checkboxes
              id: cats
              attributes:
                label: fluffy
                options:
                - label: mew mew
            - type: dropdown
              id: hampsters
              attributes:
                label: fluffy
                options:
                - "*hampster noise*"
            YAML

            config = DiscussionForms::TemplateConfig.new(input: raw_data, path: "some/path").load
            assert_predicate config, :valid?
          end

          test "two elements can have labels that result in being processed the same, if they have different IDs" do
            raw_data = <<~YAML
            ---
            body:
            - type: textarea
              id: dogs
              attributes:
                label: fluffy?
            - type: textarea
              id: cats
              attributes:
                label: fluffy!
            YAML

            config = DiscussionForms::TemplateConfig.new(input: raw_data, path: "some/path").load
            assert_predicate config, :valid?
          end
        end

        context "when some elements have user-supplied ID, IDs will be compared to processed labels" do
          test "if n elements have the same label, but (n-1) have distinct ids, the template is valid" do
            raw_data = <<~YAML
            ---
            body:
            - type: textarea
              attributes:
                label: woof
            - type: textarea
              id: woofers
              attributes:
                label: woof
            - type: textarea
              id: dogs
              attributes:
                label: woof
            YAML

            config = DiscussionForms::TemplateConfig.new(input: raw_data, path: "some/path").load
            assert_predicate config, :valid?
          end

          test "a user-supplied ID that clashes with a generated ID will be invalid" do
            raw_data = <<~YAML
            ---
            body:
            - type: textarea
              attributes:
                label: dogs
            - type: textarea
              id: 23bcd2d83d4c0f270640ec65cbeb61a1784856255c3c98dd25ec340453458348
              attributes:
                label: woof woof woof!
            YAML

            config = DiscussionForms::TemplateConfig.new(input: raw_data, path: "some/path").load
            refute_predicate config, :valid?
            assert_equal ["Body must have unique `id`s"], config.errors.full_messages
          end
        end

        context "when no elements have user-supplied ID" do
          test "returns error if two correctly-typed inputs have the same label and no IDs" do
            raw_data = <<~YAML
            ---
            body:
            - type: textarea
              attributes:
                label: meow
            - type: input
              attributes:
                label: meow
            YAML

            config = DiscussionForms::TemplateConfig.new(input: raw_data, path: "some/path").load
            refute_predicate config, :valid?
            assert_equal ["Body must have unique `label`s"], config.errors.full_messages
            assert_equal "#{@docs_link}#body-must-have-unique-labels", config.errors.first.options[:docs]
          end

          test "returns only type error if two inputs have same label, but one has invalid type" do
            raw_data = <<~YAML
            ---
            body:
            - type: textarea
              attributes:
                label: meow
            - type: party
              attributes:
                label: meow
            YAML

            config = DiscussionForms::TemplateConfig.new(input: raw_data, path: "some/path").load
            refute_predicate config, :valid?
            assert_equal ["body[1]: `party` is not a valid input type"], config.errors.full_messages
            assert_equal "#{@docs_link}#bodyi-x-is-not-a-valid-input-type", config.errors.first.options[:docs]
          end

          test "returns only invalid key error for description, if two inputs have same label but one is a description" do
            raw_data = <<~YAML
            ---
            body:
            - type: textarea
              attributes:
                label: meow
            - type: markdown
              attributes:
                label: meow
                value: some-description
            YAML

            config = DiscussionForms::TemplateConfig.new(input: raw_data, path: "some/path").load
            refute_predicate config, :valid?
            assert_equal ["body[1]: `label` is not a permitted attribute"], config.errors.full_messages
          end

          test "a label that is used at the top-level and also again in a checkbox is invalid" do
            raw_data = <<~YAML
            body:
            - type: input
              attributes:
                label: Sage
            - type: checkboxes
              attributes:
                label: Who are your favorite Valorant agents?
                description: You may select more than one.
                options:
                  - label: Sage
                  - label: Killjoy
            YAML

            config = DiscussionForms::TemplateConfig.new(input: raw_data, path: nil).load
            refute_predicate config, :valid?
            assert_equal ["Checkboxes must have unique `label`s"], config.errors.full_messages
            assert_equal "#{@docs_link}#checkboxes-must-have-unique-labels", config.errors.first.options[:docs]
          end
        end
      end

      test "returns rolled-up errors from input validations" do
        raw_data = <<~YAML
        ---
        number_of_cats: 70
        body:
        - type: not-a-type
        - type: markdown
          attributes:
            i-dont-want: no scrubs
        - type: input
          attributes:
            label: 234234234
        - invalid:
            structure: "for an input"
        YAML

        config = DiscussionForms::TemplateConfig.new(input: raw_data, path: "some/path").load
        refute_predicate config, :valid?
        assert_equal [
                         "`number_of_cats` is not a permitted key",
                         "body[0]: `not-a-type` is not a valid input type",
                         "body[1]: Required attribute key `value` is missing",
                         "body[1]: `i-dont-want` is not a permitted attribute",
                         "body[2]: `label` must be of type String and cannot be empty",
                         "body[3]: Required key `type` is missing",
                     ],
                     config.errors.full_messages
      end
    end
  end

  context "#user_inputs" do
    test "only returns inputs that accept user input" do
      raw_data = <<~YAML
      description: Create a report to help us improve
      issue_body: true
      body:
        - type: markdown
          attributes:
            value: This is a description
        - type: textarea
          attributes:
            label: Example textarea
        - type: input
          attributes:
            label: Example input
        - type: dropdown
          attributes:
            label: Example dropdown
            options:
              - One
              - Two
              - Three
      YAML

      config = DiscussionForms::TemplateConfig.new(input: raw_data, path: nil).load
      assert_equal 4, config.body.count
      assert_equal 3, config.user_inputs.count

      assert_equal "Example textarea", config.user_inputs[0].label
      assert_equal "Example input", config.user_inputs[1].label
      assert_equal "Example dropdown", config.user_inputs[2].label
    end

    test "required must be nested under validations:" do
      raw_data = <<~YAML
        ---
        body:
        - type: input
          attributes:
            label: meow
            required: true
        YAML

      config = DiscussionForms::TemplateConfig.new(input: raw_data, path: "some/path").load
      refute_predicate config, :valid?
      assert_equal ["body[0]: `required` is not a permitted attribute"], config.errors.full_messages
    end
  end
end
