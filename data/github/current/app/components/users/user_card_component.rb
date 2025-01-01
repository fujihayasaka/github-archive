# typed: true
# frozen_string_literal: true

module Users
  class UserCardComponent < ApplicationComponent
    # Instantiates a Users::UserCardComponent that can be used to render a card-like component of a user and their status and related contexts.
    # Also used in the user hovercard.
    # @param user [User] the user to render
    # @param user_status [String] _[Optional]_ - the user-set status to display on the card
    # @param user_is_sponsorable [Boolean] _[Optional]_ - whether the user is sponsorable by the viewer
    # @param viewer_is_sponsoring [Boolean] _[Optional]_ - whether the user is being sponsored by the viewer
    # @param show_staff_badge_to_viewer [Boolean] _[Optional]_ - whether to show the staff badge to the viewer if user is staff
    # @param show_pro_badge_to_viewer [Boolean] _[Optional]_ - whether to show the pro badge to the viewer if user is pro
    # @param show_user_location [Boolean] _[Optional]_ - whether to display the user's set location
    # @param show_user_local_time [Boolean] _[Optional]_ - whether to display the user's time in their set time zone
    # @param hydro_data [Hash] _[Optional]_ - contains values to send to the hydro instrumenter. Example values include:
    #   {
    #     event_type: "user_card.click",
    #     payload: { some: "stuff" }
    #   }
    # @param render_action_buttons [Boolean] _[Optional]_ - whether to render either the follow or sponsor buttons
    # @param render_follow_button [Boolean] _[Optional]_ - whether to render either the follow button
    # @param is_hovercard [Boolean] _[Optional]_ - whether we are rendering this as a hovercard or directly in the DOM
    def initialize(user:,
      user_status: nil,
      user_is_sponsorable: false,
      viewer_is_sponsoring: false,
      show_staff_badge_to_viewer: false,
      show_pro_badge_to_viewer: false,
      show_user_location: false,
      for_feed: false,
      show_user_local_time: false,
      hydro_data: {},
      render_action_buttons: true,
      render_follow_button: true,
      is_hovercard: false,
      **system_arguments
    )
      @user = user
      @user_status = user_status
      @user_is_sponsorable = user_is_sponsorable
      @viewer_is_sponsoring = viewer_is_sponsoring
      @show_staff_badge_to_viewer = show_staff_badge_to_viewer
      @show_pro_badge_to_viewer = show_pro_badge_to_viewer
      @show_user_location = show_user_location
      @for_feed = for_feed
      @show_user_local_time = show_user_local_time

      @hydro_data = hydro_data

      @render_action_buttons = render_action_buttons
      @render_follow_button = render_follow_button
      @is_hovercard = is_hovercard
      @system_arguments = system_arguments
    end

    attr_reader :user, :user_status, :viewer_is_sponsoring, :user_is_sponsorable, :show_staff_badge_to_viewer, :show_pro_badge_to_viewer, :show_user_location, :for_feed, :show_user_local_time, :hydro_data, :render_follow_button, :is_hovercard, :system_arguments

    private

    def render_action_buttons?
      @render_action_buttons ||
      @viewer_is_sponsoring  ||
      @user_is_sponsorable   ||
      @render_follow_button
    end

    def sponsor_button_location
      return :UNKNOWN unless is_hovercard
      viewer_is_sponsoring ? :HOVERCARD_SPONSORING : :HOVERCARD_SPONSOR
    end

    def card_type
      is_hovercard ? "hovercard" : "card"
    end

    def hydro_click_attrs(card_area)
      click_target = "user_#{card_type}:#{card_area}"

      if is_hovercard
        hovercard_click_hydro_attrs(click_target, data: hydro_data)
      else
        event_type = hydro_data[:event_type] || "user_#{card_type}.click"
        payload = hydro_data[:payload] || {}
        payload[:click_target] = click_target

        hydro_click_tracking_attributes(event_type, payload)
      end
    end
  end
end
