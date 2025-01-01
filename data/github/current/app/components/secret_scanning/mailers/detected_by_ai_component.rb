# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Mailers
    class DetectedByAiComponent < ApplicationComponent
      sig { returns(String) }
      def doc_url
        DocsUrlConfig.url_for("code-security/about-the-detection-of-generic-secrets-with-secret-scanning")
      end
    end
  end
end
