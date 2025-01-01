# typed: true
# frozen_string_literal: true

module Stafftools
  module User
    class ProfileHighlightContributionsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      attr_reader :user

      def page_title
        "#{user.login} - Profile Highlight Contributions"
      end

      def top_contributions(profile_highlight)
        all_contributions(profile_highlight).where(
          repository_id: profile_highlight.top_repositories.pluck(:id)
        )
      end

      def all_contributions(profile_highlight)
        profile_highlight.profile_highlight_contributions
      end

      def nasa_profile_highlight
        user.profile_highlights.find_by_highlight_type("nasa_2020")
      end
    end
  end
end
