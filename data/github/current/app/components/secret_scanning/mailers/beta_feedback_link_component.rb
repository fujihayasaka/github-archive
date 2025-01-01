# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Mailers
    class BetaFeedbackLinkComponent < ApplicationComponent
      sig { params(label_text: String, feedback_link: String).void }
      def initialize(label_text, feedback_link)
        @label_text = label_text
        @feedback_link = feedback_link
      end
    end
  end
end
