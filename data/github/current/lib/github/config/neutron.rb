# typed: strict
# frozen_string_literal: true

module GitHub
  module Config
    module Neutron
      SERVICE_NAME = "github_models"

      sig { returns(String) }
      def azure_ai_github_url
        "https://ai.azure.com/github"
      end

      sig { returns(String) }
      def azure_ai_studio_url
        "https://api.catalog.azureml.ms"
      end

      sig { returns(String) }
      def azure_ai_model_schema_url
        "https://modelcatalogcachev2-ebendjczf0c5dzca.b02.azurefd.net"
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
      def neutron_simple_box_key
        @neutron_simple_box_key ||= T.let(ENV["NEUTRON_SIMPLE_BOX_KEY"], T.nilable(String))
      end

      sig { params(key: T.nilable(String)).returns(T.nilable(String)) }
      def neutron_simple_box_key=(key = nil)
        @neutron_simple_box_key = T.let(key, T.nilable(String))
      end
    end
  end

  extend Config::Neutron
end
