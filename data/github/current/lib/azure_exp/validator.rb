# typed: true
# frozen_string_literal: true

module AzureEXP::Experiments
  module Validator
    EXPERIMENTS_SCHEMA = {
      "type": "object",
      "required": ["experiments"],
      "properties": {
        "experiments": {
          "type": "array",
          "items": { "type": "object" },
        }
      },
      "additionalProperties": false,
    }

    EXPERIMENT_SCHEMA = {
      "type": "object",
      "required": %w[
        id
        name
        description
        surface
        namespace
        feature_flag
        team
        issue
        boolean
        variants
      ],
      "properties": {
        "id": {
          "$ref": "#/$defs/nonEmptyString",
        },
        "name": {
          "$ref": "#/$defs/nonEmptyString",
        },
        "description": {
          "$ref": "#/$defs/nonEmptyString",
        },
        "surface": {
          "$ref": "#/$defs/nonEmptyString",
        },
        "namespace": {
          "$ref": "#/$defs/nonEmptyString",
        },
        "feature_flag": {
          "$ref": "#/$defs/nonEmptyString",
        },
        "team": {
          "$ref": "#/$defs/nonEmptyString",
        },
        "issue": {
          "$ref": "#/$defs/nonEmptyString",
        },
        "boolean": {
          "type": "boolean",
        },
        "variants": {
          "type": "array",
          "items": { "$ref": "#/$defs/variant" },
          "minItems": 1,
          "uniqueItems": true,
        }
      },
      "additionalProperties": false,
      "$defs": {
        "nonEmptyString": {
          "type": "string",
          "minLength": 1,
        },
        "variant": {
          "type": "object",
          "required": %w[value description],
          "properties": {
            "value": {
              "$ref": "#/$defs/nonEmptyString",
            },
            "description": {
              "$ref": "#/$defs/nonEmptyString",
            },
          },
          "additionalProperties": false
        }
      }
    }

    def self.validate(unvalidated_hash)
      # There's room for cleanup in here but I'll hold off on that until we decide we're happy with how it all
      # works from the test point of view.

      # First we validate the outer document structure
      experiments_validation_errors = JSON::Validator.fully_validate(EXPERIMENTS_SCHEMA, unvalidated_hash, parse_data: false)
      if experiments_validation_errors.any?
        trimmed_json_validation_errors = experiments_validation_errors.map do |error|
          error.sub(/ in schema .*/, "") # does this compile every time?
        end

        raise ValidationError.new(
          [FailedValidation.new(unvalidated_hash, trimmed_json_validation_errors)]
        )
      end

      # Then we validate each experiment individually.
      # Doing each experiment individually allows us to produce more friendly error messages
      failed_validations = unvalidated_hash[:experiments].filter_map do |unvalidated_exp|
        experiment_validation_errors = JSON::Validator.fully_validate(EXPERIMENT_SCHEMA, unvalidated_exp, parse_data: false)

        if experiment_validation_errors.any?
          experiment_validation_errors = experiment_validation_errors.map do |error|
            error.sub(/ in schema .*/, "") # does this compile every time?
          end

          FailedValidation.new(unvalidated_exp, experiment_validation_errors)
        else
          nil
        end
      end

      if failed_validations.any?
        raise ValidationError.new(failed_validations)
      end
    end

    class FailedValidation
      attr_reader :hash
      attr_reader :error_messages

      def initialize(hash, error_messages)
        @hash = hash
        @error_messages = error_messages
      end

      def to_s
        template =
        <<~HEREDOC

        The experiment:

        <%= JSON.pretty_generate(hash) %>


        Has the following errors:
        <% error_messages.each do |msg| %>
          * <%= msg %>
        <% end %>
        HEREDOC

        # Using ERB to produce these error messages allows for easy interpolation of the array elements
        s = ERB.new(template, trim_mode: "%<>")
        s.result(binding) # bring context into scope for ERB
      end
    end

    class ValidationError < StandardError

      attr_reader :failed_validations

      def initialize(failed_validations)
        @failed_validations = failed_validations
        super
      end

      def message
        # Might be nice to actually have the document below validated as part of testing as well
        # It would be pretty easy for it to get out of sync and become invalid as well.
        template =
        <<~HEREDOC
        <% failed_validations.each do |failed_validation| %>
          <%= failed_validation %>
        <% end %>

        Here's an example structure for a valid document:
        {
          "experiments": [
            {
              "name": "sticky_announcements",
              "description": "Sticky announcements",
              "id": "Fe1444",
              "surface": "feeds",
              "namespace": "feeds",
              "feature_flag": "multiple_pinned_announcements",
              "team": "Feeds",
              "issue": "https://github.com/github/feed/1234",
              "variants": [
                {
                  "value": "A",
                  "description": "Sticky announcements enabled"
                },
                {
                  "value": "B",
                  "description": "Sticky announcements disabled"
                }
              ]
            }
          ]
        }
        HEREDOC

        s = ERB.new(template, trim_mode: "%<>")
        s.result(binding) # bring context into scope for ERB
      end
    end
  end
end
