# typed: true
# frozen_string_literal: true

module Hovercards
  class UserCardComponent < ApplicationComponent
    def initialize(user:,
      user_status: nil,
      user_is_sponsorable: false,
      viewer_is_sponsoring: false,
      show_staff_badge_to_viewer: false,
      show_pro_badge_to_viewer: true,
      show_user_location: true,
      show_user_local_time: true,
      hovercard_contexts: [],
      hydro_data: {},
      **system_arguments
    )
      @user = user
      @user_status = user_status
      @user_is_sponsorable = user_is_sponsorable
      @viewer_is_sponsoring = viewer_is_sponsoring
      @show_staff_badge_to_viewer = show_staff_badge_to_viewer
      @show_pro_badge_to_viewer = show_pro_badge_to_viewer
      @show_user_location = show_user_location
      @show_user_local_time = show_user_local_time

      @hovercard_contexts = hovercard_contexts
      @hydro_data = hydro_data
      @system_arguments = system_arguments
    end

    attr_reader :user, :user_status, :viewer_is_sponsoring, :user_is_sponsorable, :show_staff_badge_to_viewer, :show_pro_badge_to_viewer, :show_user_location, :show_user_local_time, :hovercard_contexts, :hydro_data, :render_follow_button, :system_arguments

    def icon_label(context)
      if context.is_a?(UserHovercard::Contexts::OrganizationTeams)
        "team"
      elsif context.is_a?(UserHovercard::Contexts::Organizations)
        "organization"
      else
        context.octicon.humanize
      end
    end
  end
end
