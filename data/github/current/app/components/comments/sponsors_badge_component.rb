# typed: true
# frozen_string_literal: true

module Comments
  class SponsorsBadgeComponent < ApplicationComponent
    include ResilienceHelper

    # sponsorship - Sponsorship between comment author and repository owner
    #   where comment author is the sponsor and the repository owner is the
    #   sponsorable.
    def initialize(sponsorship)
      @sponsorship = sponsorship
    end

    private

    attr_reader :sponsorship

    delegate :sponsorable_login, :sponsorship_created_at, to: :sponsorship

    def render?
      return false unless GitHub.sponsors_enabled?
      return false if sponsorship.nil?

      with_database_error_fallback(fallback: false) { sponsorship.sponsor_readable_by?(current_user) }
    end

    def current_user_is_author?
      return false unless logged_in?

      current_user.display_login == sponsorable_login
    end

    def author_term_and_verb
      if current_user_is_author?
        "Your sponsor"
      else
        "#{sponsorable_login}'s sponsor"
      end
    end

    def title
      "Sponsor"
    end
  end
end
