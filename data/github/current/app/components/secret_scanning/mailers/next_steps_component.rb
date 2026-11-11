# typed: true
# frozen_string_literal: true

module SecretScanning
  module Mailers
    class NextStepsComponent < ApplicationComponent
      def initialize(review_link_text:, review_url:, cta_message:, cta_button_text:, cta_button_url:)
        @review_link_text = review_link_text
        @review_url = review_url
        @cta_message = cta_message
        @cta_button_text = cta_button_text
        @cta_button_url = cta_button_url
      end
    end
  end
end
