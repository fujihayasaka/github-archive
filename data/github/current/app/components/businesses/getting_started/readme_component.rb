# typed: true
# frozen_string_literal: true

module Businesses
  module GettingStarted
    class ReadmeComponent < ViewComponent::Base
      attr_reader :business, :current_user

      def initialize(business:, current_user:)
        @business = business
        @current_user = current_user
      end

      def owner?
        business.owner?(current_user)
      end

      def javascript_packs
        ["businesses/readme-component"]
      end
    end
  end
end
