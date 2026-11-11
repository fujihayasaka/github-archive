# typed: strict
# frozen_string_literal: true

module CopilotModelRegistry
  # Calls the internal Copilot API to generate AI feedback on model YAML configurations.
  # Follows the same pattern as PR Summary Generation (copilot4prs).
  class AiReviewService

    PROMPT_TEMPLATE_PATH = T.let(
      File.expand_path("templates/ai_review_prompt.md", __dir__).freeze,
      String,
    )

    sig { params(current_user: User).void }
    def initialize(current_user)
      @current_user = current_user
    end

    # Generates AI feedback for a pending model change.
    # Returns a hash with :ai_feedback (String, markdown) and :prompt_used (String).
    sig do
      params(
        proposed_yaml: String,
        current_yaml: T.nilable(String),
        diff_text: T.nilable(String),
        existing_models_yaml: String,
        is_new_model: T::Boolean,
      ).returns(T::Hash[Symbol, String])
    end
    def review(proposed_yaml:, current_yaml: nil, diff_text: nil, existing_models_yaml: "", is_new_model: false)
      rendered_prompt = render_prompt({
        current_model: proposed_yaml,
        existing_model: current_yaml || "(No previous version — this is a new model)",
        diff: diff_text || "(No diff available)",
        existing_models: existing_models_yaml,
        is_new_model: is_new_model.to_s,
      })

      ai_feedback = call_copilot_api(rendered_prompt)

      {
        ai_feedback: ai_feedback,
        prompt_used: rendered_prompt,
      }
    end

    # Builds a YAML summary of all existing models for context injection.
    # Only includes key fields to keep the prompt concise.
    sig { params(models: T::Array[T::Hash[Symbol, T.untyped]]).returns(String) }
    def self.summarize_existing_models(models)
      return "(No existing models in registry)" if models.empty?

      summaries = models.map do |m|
        yaml_content = m[:yaml_content].to_s
        if yaml_content.present?
          data = begin
            YAML.safe_load(yaml_content)
          rescue StandardError
            nil
          end
          if data
            <<~SUMMARY
              - referenceID: #{data["referenceID"]}
                name: #{data["name"]}
                policyID: #{data["policyID"]}
                vendor: #{data["vendor"]}
                modelAvailability: #{data["modelAvailability"]}
                id: #{data["id"]}
                featureFlag: #{data["featureFlag"]}
                billing.restrictedTo: #{(data.dig("billing", "restrictedTo") || []).join(", ")}
                endpoints: #{(data["endpoints"] || []).map { |e| e["name"] }.compact.join(", ")}
            SUMMARY
          else
            "  - referenceID: #{m[:reference_id]} (could not parse YAML)"
          end
        else
          "  - referenceID: #{m[:reference_id]} name: #{m[:name]} vendor: #{m[:vendor]}"
        end
      end
      summaries.join("\n")
    end

    private

    sig { params(variables: T::Hash[Symbol, String]).returns(String) }
    def render_prompt(variables)
      template = File.read(PROMPT_TEMPLATE_PATH)
      variables.each do |key, value|
        template = template.gsub("{#{key}}", value.to_s)
      end
      template
    end

    sig { params(prompt: String).returns(String) }
    def call_copilot_api(prompt)
      messages = [
        { role: "system", content: "You are an expert reviewer of Copilot model registry YAML configurations." },
        { role: "user", content: prompt },
      ]

      begin
        response = T.cast(
          CopilotAPI.make_request(
            token: nil,
            integration_id: copilot_integration_id,
            user_id: @current_user.id.to_s,
            real_ip: nil,
            method: :post,
            path: "/chat/completions",
            data: {
              model: "gpt-4.1",
              messages: messages,
              max_tokens: 2048,
              temperature: 0.3,
            },
          ),
          ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess],
        )

        if response.status == 200
          body = JSON.parse(response.body)
          body.dig("choices", 0, "message", "content") || "No feedback generated."
        else
          "AI review request failed (status: #{response.status}). Please try again."
        end
      rescue StandardError => e
        GitHub.logger.error("CopilotModelRegistry AI review failed", error: e.message)
        "AI review unavailable: #{e.message}"
      end
    end

    sig { returns(String) }
    def copilot_integration_id
      # This integration ID must be registered in config/initializers/copilot_api.rb
      # Requires Copilot platform team approval. Until then, the feature is gated
      # behind the copilot_model_registry_review_workflow feature flag.
      "copilot-model-registry-review"
    end
  end
end
