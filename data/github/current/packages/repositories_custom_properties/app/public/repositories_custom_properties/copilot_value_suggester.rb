# typed: strict
# frozen_string_literal: true

module RepositoriesCustomProperties
  class CopilotValueSuggester
    README_CHARACTER_LIMIT = 10_000

    class GenerationError < StandardError; end

    sig do
      params(
        repository: Repository,
        definition: CustomPropertiesCore::IPropertyDefinition,
        copilot_api: Copilot::User::CopilotApi,
      ).void
    end
    def initialize(repository:, definition:, copilot_api:)
      @repository = repository
      @definition = definition
      @copilot_api = copilot_api
    end

    sig { returns(T::Hash[String, T.untyped]) }
    def suggest
      response = GitHub.dogstats.time("copilot_api.suggest_custom_property_value.timing") do
        result = @copilot_api.create_chat_completion(
          model: "gpt-4o-mini",
          messages: messages,
          max_tokens: 500,
          temperature: 0.3,
          response_format: response_format,
        )
        result.is_a?(ConcurrentFaraday::FutureResponse) ? result.value : result
      end

      log_token_usage(response)

      generated_text = response.dig("choices", 0, "message", "content")
      JSON.parse(generated_text)
    rescue JSON::ParserError => e
      GitHub.logger.error("Failed to parse Copilot API response for suggest repo property value", "error" => e.message, "raw_response" => generated_text)
      raise GenerationError
    rescue => e
      GitHub.logger.error("Failed to generate suggestion for suggest repo property value", "error" => e.message)
      raise GenerationError
    end

    private

    sig { params(response: T::Hash[String, T.untyped]).void }
    def log_token_usage(response)
      usage = response["usage"]
      return unless usage.is_a?(Hash)

      prompt_tokens = usage["prompt_tokens"]
      completion_tokens = usage["completion_tokens"]

      GitHub.dogstats.histogram("copilot_api.suggest_custom_property_value.prompt_tokens", prompt_tokens) if prompt_tokens
      GitHub.dogstats.histogram("copilot_api.suggest_custom_property_value.completion_tokens", completion_tokens) if completion_tokens
    end

    sig { returns(T::Array[T::Hash[String, String]]) }
    def messages
      [
        { "role": "system", "content": system_prompt },
        { "role": "user", "content": user_prompt },
      ]
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def response_format
      {
        type: "json_schema",
        json_schema: {
          name: "custom_property_value_suggestion",
          strict: true,
          schema: {
            type: "object",
            properties: {
              value: { type: %w[string null], description: "The suggested value for the custom property" },
              explanation: { type: "string", description: "A brief explanation of why this value was suggested based on the README content" },
            },
            required: %w[value explanation],
            additionalProperties: false,
          },
        },
      }
    end

    sig { returns(String) }
    def system_prompt
      <<~PROMPT
        You are an expert at classifying GitHub repositories based on their content.
        Given the following repository name, README (if it exists), and custom property definition, suggest the most appropriate value for this property.
        Consider the existing value of this property if it's set, but you can suggest a different value if the README content justifies it.

        If the property has allowed values, you MUST pick from those values.
        If the value type is true_false, respond with "true" or "false".
        If the property has a Regex, the value must satisfy it.
        If the property does not require explicit values, an empty value is acceptable if the README does not provide enough information to make a suggestion.
      PROMPT
    end

    sig { returns(String) }
    def user_prompt
      readme_content = @repository.preferred_readme&.data.to_s.truncate(README_CHARACTER_LIMIT)
      current_value = Repositories.domain.custom_properties.repo_properties([@repository], :effective)[@repository]&.dig(@definition.property_name)

      <<~PROMPT
        ## Repository name
        #{@repository.name}

        ## Repository README
        #{readme_content}

        ## Custom Property Definition
        - Name: #{@definition.property_name}
        - Description: #{@definition.description}
        - Value type: #{@definition.value_type}
        #{@definition.allowed_values ? "- Allowed values: #{@definition.allowed_values&.join(", ")}" : ""}
        #{@definition.is_a?(CustomPropertyDefinition) ? "- Explicit values required: #{@definition.require_explicit_values}" : ""}
        - Required: #{@definition.required}
        #{@definition.regex ? "- Regex: #{@definition.regex}" : ""}

        ## Current property value
        #{current_value}
      PROMPT
    end
  end
end
