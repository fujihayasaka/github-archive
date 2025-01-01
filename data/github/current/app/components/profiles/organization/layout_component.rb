# typed: true
# frozen_string_literal: true

module Profiles
  module Organization
    class LayoutComponent < ApplicationComponent
      def initialize(layout_data:)
        @layout_data = layout_data
      end

      private

      attr_reader :layout_data

      delegate(
        :avatar_for,
        :mobile?,
        to: :helpers,
      )
    end
  end
end
