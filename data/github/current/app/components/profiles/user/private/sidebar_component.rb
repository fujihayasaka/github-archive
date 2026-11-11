# typed: true
# frozen_string_literal: true

module Profiles
  module User
    module Private
      class SidebarComponent < ApplicationComponent
        extend T::Helpers

        sig { params(profile_layout_data: T.untyped, gists_profile: T.untyped).void }
        def initialize(profile_layout_data:, gists_profile: false)
          @profile_layout_data = profile_layout_data
          @gists_profile = gists_profile
        end

        def render?
          !hide_from_viewer?
        end

        private

        attr_reader :profile_layout_data

        delegate(
          :follow_button,
          :profile_click_tracking_attrs,
          :profile_avatar_using,
          to: :helpers,
        )

        delegate(
          :show_follow_button?,
          :user_is_viewer?,
          :primary_avatar_url,
          :profile_name,
          :profile_user,
          :login_name,
          :site_admin?,
          :user_is_viewer?,
          :viewer_blocking_profile_user?,
          :ignored_user_record,
          :hide_from_viewer?,
          to: :profile_layout_data,
        )

        def gists_profile?
          @gists_profile
        end
      end
    end
  end
end
