# typed: strict
# frozen_string_literal: true

module SecretScanning
  module AlertCentricView
    module Blankslates
      class NoReposWithSecretScanningEnabledComponent < ApplicationComponent
        sig { params(organization: Organization).void }
        def initialize(organization:)
          @organization = organization
        end

        sig { returns(String) }
        def icon_animation_class
          "secret-scanning-shield-animate"
        end
      end
    end
  end
end
