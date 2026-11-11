# typed: strict
# frozen_string_literal: true

module SecretScanning
  module AlertCentricView
    module Blankslates
      class NoOrganizationsComponent < ApplicationComponent
        sig { params(business: Business).void }
        def initialize(business:)
          @business = business
        end
      end
    end
  end
end
