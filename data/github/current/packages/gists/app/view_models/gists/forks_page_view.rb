# typed: true
# frozen_string_literal: true

module Gists
  # Controls the forks page
  # eg https://github.com/gists/spicycode/:uid/forks
  class ForksPageView < ShowPageView
    include ForkCountingMethods

    PER_PAGE = 51

    attr_reader :gist, :current_page

    def page_title
      "Forks · #{gist.title}"
    end

    def active_forks
      forks.owned.modified
    end

    def stale_forks
      forks.owned.stale
    end

    def has_forks?
      fork_count > 0
    end
  end
end
