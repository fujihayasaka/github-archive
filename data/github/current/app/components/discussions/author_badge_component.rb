# typed: true
# frozen_string_literal: true

module Discussions
  # Public: Used to display an 'Author' badge on comments in a discussion, to identify the original
  # poster who started a discussion. Does not determine if the given user is that discussion author,
  # so should only be rendered when that is the case.
  class AuthorBadgeComponent < ApplicationComponent
    # author - a User, the author of a discussion comment
    def initialize(author:)
      @author = author
    end

    private

    attr_reader :author

    def current_user_is_author?
      author && current_user == author
    end

    def render?
      !author.ghost?
    end

    def author_term_and_verb
      if current_user_is_author?
        "You are"
      else
        "This user is"
      end
    end

    def title
      "#{author_term_and_verb} the author of this discussion."
    end
  end
end
