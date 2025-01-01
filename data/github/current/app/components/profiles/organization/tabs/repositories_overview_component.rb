# typed: true
# frozen_string_literal: true

module Profiles
  module Organization
    module Tabs
      class RepositoriesOverviewComponent < Profiles::BaseRepositoriesOverviewComponent

        # Check if the user or viewer is an organization member.
        #
        # Returns Boolean
        def is_member?
          return @is_member if defined?(@is_member)
          @is_member = profile_user.member?(current_user)
        end

        # Check if the user or viewer should see the default message when no pinned repositories.
        #
        # Returns Boolean
        def show_empty_state?
          return @show_empty_state if defined?(@show_empty_state)

          @show_empty_state = enterprise_managed_user_enabled? && !has_pinned_items?
        end

        # Check if the viewer is a member who has permissions to change pinned items
        def hide_pinned_or_popular_items?
          if enterprise_managed_user_enabled?
            true
          else
            is_member? && !has_pinned_items?
          end
        end

        # Determines whether the ViewComponent should render for members when no pinned repositories.
        #
        # Returns Boolean
        def render?
          return @render if defined?(@render)
          # should still show popular repositories to non-members if any repos exist and render for EMU if any repos exist
          @render = (viewing_as_member? && has_pinned_items?) || (!viewing_as_member? && items.any?) || (enterprise_managed_user_enabled? && any_pinnable_items?)
        end

        # Constructs the title to be shown if no pinned repositories.
        #
        # Returns String
        def blank_title
          parts = [
            user_is_viewer? ? "You don't" : "#{profile_user.display_login} doesn't",
            "have any pinned",
            GitHub.public_repositories_available? && !enterprise_managed_user_enabled? && !viewing_as_member? ? "public" : nil,
            "repositories yet.",
          ]

          parts.compact.join(" ")
        end
      end
    end
  end
end
