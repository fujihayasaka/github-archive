# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module Models
      SERVICE_NAME = "github_models"

      sig { returns(String) }
      def azure_ai_github_url
        "https://ai.azure.com/github"
      end

      sig { params(models_gateway_url: String).void }
      attr_writer :models_gateway_url
      sig { returns(String) }
      def models_gateway_url
        @models_gateway_url.presence || "https://models.github.ai"
      end

      sig { returns(String) }
      def azure_ai_studio_url
        "https://api.catalog.azureml.ms"
      end

      sig { returns(String) }
      def azure_ai_model_schema_url
        "https://ai.azure.com"
      end

      sig { returns(String) }
      def azure_ai_playground_url
        "https://models.inference.ai.azure.com"
      end

      sig { returns(String) }
      def azure_ai_publishers_url
        "https://eastus2euap.api.azureml.ms"
      end

      sig { returns(T.nilable(String)) }
      def models_simple_box_key
        @models_simple_box_key ||= T.let(ENV["NEUTRON_SIMPLE_BOX_KEY"], T.nilable(String))
      end

      sig { params(key: T.nilable(String)).returns(T.nilable(String)) }
      def models_simple_box_key=(key = nil)
        @models_simple_box_key = T.let(key, T.nilable(String))
      end
    end
  end

  extend Config::Models
end
