# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Mailers
    class NextStepsForPatComponent < ApplicationComponent
      extend T::Sig

      sig { params(cta_message: String, cta_button_text: String, cta_button_url: String).void }
      def initialize(cta_message:, cta_button_text:, cta_button_url:)
        @cta_message = cta_message
        @cta_button_text = cta_button_text
        @cta_button_url = cta_button_url
      end
    end
  end
end
