# typed: strict
# frozen_string_literal: true

module CodeScanning
  module Blankslates
    class NotEnabledComponent < ApplicationComponent
      sig { params(organization: Organization).void }
      def initialize(organization:)
        @organization = organization
      end
    end
  end
end
