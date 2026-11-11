# typed: strict
# frozen_string_literal: true

require "monolith-twirp-copilot-registry"

module CopilotModelRegistry
  module Twirp
    class ModelClient < CopilotModelRegistry::Twirp::BaseClient
      include GitHub::Memoizer

      # This method calls the limiter and gets the consumptive user stuff
      sig { returns(T::Array[CopilotModel]) }
      def get_models
        GitHub.logger.with_named_tags({
          "code.function": "get_models",
          "code.namespace": "CopilotModelRegistry::Twirp::ModelRegistryClient",
        }) do
          GitHub.logger.info("Getting models from Copilot Model Registry via Twirp")

          response = rpc(:GetModels, {})

          GitHub.logger.info(
            "Finished Twirp Call",
            "gh.copilot_model_registry.response.status": response&.status,
            "gh.copilot_model_registry.response.call_succeeded": response&.call_succeeded,
          )

          if response&.call_succeeded?
            GitHub.dogstats.increment("copilot_model_registry.model_client.success", tags: { method: "get_models" })
            parse_models_response(response.value)
          else
            failbot_report(response&.status || CopilotModelRegistry::Twirp::Error.new("Twirp call failed for GetModels"))
            GitHub.dogstats.increment("copilot_model_registry.model_client.failure", tags: { method: "get_models", status: response.status })
            GitHub.logger.info("Failed to get models call")
            []
          end
        end
      end

      private

      sig { returns(T.class_of(::MonolithTwirp::Copilot::Registry::V1::CopilotRegistryAPIClient)) }
      def twirp_class
        ::MonolithTwirp::Copilot::Registry::V1::CopilotRegistryAPIClient
      end

      # Typed hash representing a parsed model
      CopilotModel = T.type_alias do
        {
          key: String,
          name: String,
          description: String,
          plans: T::Array[String],
          feature_flag: String,
          internal: T::Boolean,
          preview: T::Boolean,
          documentation_link: String,
          documentation_link_text: String,
          inline_approval_enabled: T::Boolean,
        }
      end

      sig do
        params(
          response: MonolithTwirp::Copilot::Registry::V1::GetModelsResponse
        ).returns(T::Array[CopilotModel])
      end
      def parse_models_response(response)
        model_details = response.model_details
        models = T.let(
          model_details.map do |model|
            {
              key: model.reference_id,
              name: model.name,
              description: "A #{model.vendor} model. Version: #{model.version}.", # customize as needed
              plans: model.billing.restricted_to,
              feature_flag: model.feature_flag,
              internal: !model.is_model_picker_enabled,
              preview: model.is_preview,
              documentation_link: model.documentation_link,
              documentation_link_text: model.documentation_link_text,
              inline_approval_enabled: model.inline_approval&.enabled || false,
            }
          end,
          T::Array[CopilotModel]
        )
        models.freeze
      end
    end
  end
end
