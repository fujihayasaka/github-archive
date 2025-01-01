# typed: true
# frozen_string_literal: true

module SecretScanning
  module Mailers
    class RemediationSubStepComponent < ApplicationComponent
      def initialize(link_url:, link_text:, follow_up_text:)
        @link_url = link_url
        @link_text = link_text
        @follow_up_text = follow_up_text
      end
    end
  end
end
