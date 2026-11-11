# typed: strict
# frozen_string_literal: true

module Copilot
  module Checkout
    class AccountSectionComponent < ApplicationComponent
      sig { params(user: ::User).void }
      def initialize(user:)
        @user = user
      end

      private

      sig { returns(::User) }
      attr_reader :user
    end
  end
end
