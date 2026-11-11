# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Mailers
    class NextStepsForRevokeComponent < ApplicationComponent
      sig { params(alert_url: String).void }
      def initialize(alert_url:)
        @alert_url = alert_url
      end
    end
  end
end
