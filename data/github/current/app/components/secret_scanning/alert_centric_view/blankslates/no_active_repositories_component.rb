# typed: strict
# frozen_string_literal: true

module SecretScanning
  module AlertCentricView
    module Blankslates
      class NoActiveRepositoriesComponent < ApplicationComponent
        sig { params(organization: Organization).void }
        def initialize(organization:)
          @organization = organization
        end
      end
    end
  end
end
