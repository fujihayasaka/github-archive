# typed: true
# frozen_string_literal: true

module Profiles
  module User
    module Private
      class LayoutComponent < ApplicationComponent
        include GlobalNavigationHelper
        extend T::Helpers

        sig { params(layout_data: T.untyped).void }
        def initialize(layout_data:)
          @layout_data = layout_data
        end

        private

        attr_reader :layout_data

        delegate(
          :avatar_for,
          :follow_button,
          to: :helpers,
        )
      end
    end
  end
end
