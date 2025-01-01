# typed: strict
# frozen_string_literal: true

module GitHub
  module Config
    module CopilotByok
      SERVICE_NAME = "copilot_byok"

      sig { returns(String) }
      def openai_api_url
        "https://api.openai.com"
      end
    end
  end

  extend Config::CopilotByok
end
