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
    end
  end

  extend Config::ModelsByok
end
