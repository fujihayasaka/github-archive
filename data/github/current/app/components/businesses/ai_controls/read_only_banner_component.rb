# typed: strict
# frozen_string_literal: true

module Businesses
  module AiControls
    class ReadOnlyBannerComponent < ApplicationComponent
      sig { params(is_admin: T::Boolean).void }
      def initialize(is_admin:)
        @is_admin = is_admin
      end

      sig { returns(T::Boolean) }
      def render?
        !@is_admin
      end
    end
  end
end
