# typed: strict
# frozen_string_literal: true

module Profiles
  module User
    class LayoutComponent < ApplicationComponent
      include GlobalNavigationHelper
      extend T::Helpers
      extend T::Sig

      sig { params(layout_data: T.untyped).void }
      def initialize(layout_data:)
        @layout_data = layout_data
      end

      private

      sig { returns(T.untyped) }
      attr_reader :layout_data

      delegate(
        :avatar_for,
        :follow_button,
        to: :helpers,
      )
    end
  end
end
