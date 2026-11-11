# typed: strict
# frozen_string_literal: true

module CodeScanning
  module Blankslates
    class NoActiveRepositoriesEnterpriseComponent < ApplicationComponent
      sig { params(business: Business, organizations: T::Array[Organization]).void }
      def initialize(business:, organizations:)
        @business = business
        @organizations = organizations
      end
    end
  end
end
