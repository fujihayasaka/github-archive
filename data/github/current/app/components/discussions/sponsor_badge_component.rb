# typed: true
# frozen_string_literal: true

module Discussions
  # Public: Used to display an 'Sponsor' badge on comments in a discussion
  class SponsorBadgeComponent < ApplicationComponent
    # author - a User, the author of a discussion comment
    # timeline - a DiscussionTimeline
    def initialize(author:, timeline:)
      @author = author
      @timeline = timeline
    end

    def call
      render(Primer::Beta::Label.new(
        title: title,
        py: 0,
        ml: 1,
      ).with_content("Sponsor"))
    end

    private

    attr_reader :author, :timeline

    def current_user_is_author?
      current_user == author
    end

    def render?
      GitHub.sponsors_enabled? && author && !author.ghost? && timeline && sponsorable &&
        timeline.author_is_sponsor?(author.id)
    end

    memoize def sponsorable
      timeline.repo_owner
    end

    def author_term_and_verb
      if current_user_is_author?
        "You are"
      else
        "This user is"
      end
    end

    def title
      "#{author_term_and_verb} sponsoring #{sponsorable}."
    end
  end
end
