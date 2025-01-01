# typed: true
# frozen_string_literal: true

module SecretScanning
  module Mailers
    class RemediationStepComponent < ApplicationComponent
      def initialize(number:, message:, review_link_text:, review_url:)
        @number = number
        @message = message
        @review_link_text = review_link_text
        @review_url = review_url
      end

      def contains_substeps?
        return false unless @review_link_text || @review_url
        true
      end
    end
  end
end
