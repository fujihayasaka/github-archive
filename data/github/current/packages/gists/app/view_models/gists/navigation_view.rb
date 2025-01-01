# typed: true
# frozen_string_literal: true

module Gists
  class NavigationView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include ActionView::Helpers::NumberHelper
    include ForkCountingMethods

    attr_reader :gist

    delegate :owner, :user_param, :stargazer_count, to: :gist

    def logged_in?
      !!current_user
    end

    def show_stars?
      stargazer_count > 0
    end

    def show_forks?
      fork_count > 0
    end

    def revisions_count(limit = 10_000)
      # Handle cases on legacy gists (gists with integer repo names) that have
      # routing issues
      return 0 if gist.sha.blank?

      count = gist.rpc.fast_commit_count(gist.sha, limit)

      if count == limit
        "#{number_with_delimiter count}+"
      else
        number_with_delimiter count
      end
    end

    def show_revisions?
      revisions_count.to_i > 0
    end

    # What symbols should we trigger highlighting for various tabs?
    def highlights_for_code
      [:gist_code]
    end

    def highlights_for_stars
      [:gist_stars]
    end

    def highlights_for_forks
      [:gist_forks]
    end

    def highlights_for_revisions
      [:gist_revisions]
    end
  end
end
