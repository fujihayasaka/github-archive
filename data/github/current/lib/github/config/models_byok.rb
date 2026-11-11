# typed: strict
# frozen_string_literal: true

module GitHub
  module Config
    module ModelsByok
      SERVICE_NAME = "models_byok"

      sig { returns(String) }
      def openai_api_url
        "https://api.openai.com"
      end

      sig { returns(String) }
      def anthropic_api_url
        "https://api.anthropic.com"
      end

      sig { returns(String) }
      def google_ai_studio_api_url
        "https://generativelanguage.googleapis.com"
      end

      sig { returns(String) }
      def xai_api_url
        "https://api.x.ai"
      end
    end
  end

  extend Config::ModelsByok
end
