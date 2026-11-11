# typed: true
# frozen_string_literal: true

module Profiles
  module ProfilePins
    class PinnedItemsComponent < ApplicationComponent
      def initialize(show_button_name:, profile_user:, view_as: nil, viewing_as_member: nil, data:, dialog_location:)
        @show_button_name = show_button_name
        @profile_user = profile_user
        @view_as = view_as
        @viewing_as_member = !!viewing_as_member
        @data = data
        @dialog_location = dialog_location
      end

      private

      attr_reader :show_button_name, :profile_user, :view_as, :viewing_as_member, :data, :dialog_location

      def title
        profile_user.user? ? "Edit pinned items" : "Edit pinned repositories"
      end
    end
  end
end
