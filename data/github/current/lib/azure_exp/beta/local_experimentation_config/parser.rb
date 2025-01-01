# typed: strict
# frozen_string_literal: true

module AzureEXP::Beta::LocalExperimentationConfig
  module Parser
    extend T::Sig

    NAMESPACE_SCHEMA = T.let({
      "type": "object",
      "required": %w[
        name
        experiments
      ],
      "properties": {
        "name": {
          "$ref": "#/$defs/nonEmptyString",
        },
        "experiments": {
          "type": "array",
          "items": { "$ref": "#/$defs/experiment" },
        }
      },
      "additionalProperties": false,
      "$defs": {
        "nonEmptyString": {
          "type": "string",
          "minLength": 1,
        },
        "experiment": {
          "type": "object",
          "required": %w[
            name
            variants
          ],
          "properties": {
            "name": {
              "$ref": "#/$defs/nonEmptyString",
            },
            "variants": {
              "type": "array",
              "items": { "$ref": "#/$defs/variant" },
              "minItems": 1,
            }
          },
          "additionalProperties": false
        },
        "variant": {
          "type": "object",
          "required": %w[
            name
            parameters
          ],
          "properties": {
            "name": {
              "$ref": "#/$defs/nonEmptyString",
            },
            "details": {
              "type": "string",
            },
            "parameters": {
              "type": "object",
              "patternProperties": {
                "^.*$": { "type": %w[boolean number string] },
              },
            }
          },
        }
      }
    }, T::Hash[Symbol, T.untyped])

    sig { params(unparsed_hash: T::Hash[Symbol, T.untyped]).returns(AzureEXP::Beta::LocalExperimentationConfig::Config) }
    def self.parse(unparsed_hash)
      # Note we don't test the outer shape, only each namespace since that is the shape most likely to cause trouble.
      # Technically if we pass this a hash without a `:namespaces` symbol it will blow up.
      failed_validations = unparsed_hash[:namespaces].filter_map do |unparsed_namespace|
        namespace_validation_errors =
          JSON::Validator.fully_validate(NAMESPACE_SCHEMA, unparsed_namespace, parse_data: false)

        if namespace_validation_errors.any?
          # Remove the "in schema (XYZ)" trailing text that JSON schema validation produces
          # because it's more confusing than helpful.
          namespace_validation_errors = namespace_validation_errors.map do |error|
            error.sub(/ in schema .*/, "")
          end

          FailedParse.new(unparsed_namespace, namespace_validation_errors)
        else
          nil
        end
      end

      if failed_validations.any?
        raise ParseError.new(failed_validations)
      end

      AzureEXP::Beta::LocalExperimentationConfig::Config.new(
        namespaces: unparsed_hash[:namespaces].map do |namespace|
          AzureEXP::Beta::LocalExperimentationConfig::Namespace.new(
            name: namespace[:name],
            experiments: namespace[:experiments].map do |experiment|
              AzureEXP::Beta::LocalExperimentationConfig::Experiment.new(
                name: experiment[:name],
                variants: experiment[:variants].map do |variant|
                  AzureEXP::Beta::LocalExperimentationConfig::Variant.new(
                    name: variant[:name],
                    details: variant[:details],
                    parameters: variant[:parameters].stringify_keys
                  )
                end
              )
            end
          )
        end
      )
    end

    class FailedParse
      extend T::Sig

      sig { returns(T::Hash[Symbol, T.untyped]) }
      attr_reader :hash

      sig { returns(T::Array[String]) }
      attr_reader :error_messages

      sig { params(hash: T::Hash[Symbol, T.untyped], error_messages: T::Array[String]).void }
      def initialize(hash, error_messages)
        @hash = hash
        @error_messages = error_messages
      end

      sig { returns(String) }
      def to_s
        template =
        <<~HEREDOC

        The namespace with content:

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

    class ParseError < StandardError
      extend T::Sig

      sig { returns(T::Array[FailedParse]) }
      attr_reader :failed_validations

      sig { params(failed_validations: T::Array[FailedParse]).void }
      def initialize(failed_validations)
        @failed_validations = failed_validations
        super
      end

      sig { returns(String) }
      def message
        # Might be nice to actually have the document below validated as part of testing as well
        # It would be pretty easy for it to get out of sync and become invalid as well.
        template =
        <<~HEREDOC
        <% failed_validations.each do |failed_parse| %>
          <%= failed_parse %>
        <% end %>

        Here's an example structure for a valid document:
        {
          "name": "test_namespace",
          "experiments: [
            {
              "name": "test_experiment",
              "variants": [
                {
                  "name": "treatment",
                  "parameters": {
                    "button_color": "red",
                    "font_size": 12
                  }
                },
                {
                  "name": "control",
                  "parameters": {
                    "button_color": "blue",
                    "font_size": 14
                  }
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
