# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module Figma

      sig { returns(String) }
      def api_key
        GitHub.environment.fetch("FIGMA_API_KEY", "figma_api_key")
      end

      sig { returns(::Figma::Client) }
      def figma_client
        @figma_client ||= ::Figma::Client.new(api_key)
      end
    end
  end

  extend Config::Figma
end
