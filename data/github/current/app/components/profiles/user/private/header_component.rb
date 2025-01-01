# typed: true
# frozen_string_literal: true

module Profiles
  module User
    module Private
      class HeaderComponent < ApplicationComponent

        def initialize(viewer:, profile_user:, previewing:, tab: nil)
          @viewer = viewer
          @profile_user = profile_user
          @previewing = previewing
          @tab = tab
        end

        def render?
          profile_user.private_profile? && profile_user == viewer
        end

        def button_text
          if previewing
            "View full profile"
          else
            "View what others see"
          end
        end

        def button_link
          params = {}

          # If we're not currently previewing the "what others see" profile view, pass the
          # :preview param so the button toggles from the current "full profile" view to the
          # preview of what others see.
          params[:preview] = true unless previewing

          # If we're previewing on a specific tab, pass that along to toggle between
          # full/preview on that tab.
          params[:tab] = tab if tab

          user_path(profile_user, params: params)
        end

        def feedback_url
          "#{GitHub.url}/github/feedback/discussions/categories/profile"
        end

        private

        attr_reader :viewer, :profile_user, :previewing, :tab
      end
    end
  end
end
