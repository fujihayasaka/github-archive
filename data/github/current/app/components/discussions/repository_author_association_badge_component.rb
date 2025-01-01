# typed: true
# frozen_string_literal: true

module Discussions
  # Public: Used to display the relationship between a given user and a repository,
  # such as if the user is a collaborator, maintainer, or contributor to the
  # repository.
  class RepositoryAuthorAssociationBadgeComponent < ApplicationComponent
    # author - a User, the author of a discussion or discussion comment
    # action_or_role_level - Symbol representing the user's action or role level within
    #                        the repository containing the discussion or discussion
    #                        comment this badge is displayed for; e.g., :maintain, :write
    def initialize(author:, action_or_role_level:)
      @author = author
      @action_or_role_level = action_or_role_level
    end

    private

    attr_reader :author, :action_or_role_level

    def current_user_is_author?
      author && current_user == author
    end

    def render?
      role_name && !author.ghost?
    end

    memoize def role_name
      if author_is_collaborator?
        "Collaborator"
      elsif author_is_maintainer?
        "Maintainer"
      end
    end

    def author_is_collaborator?
      [:triage, :write].include?(action_or_role_level)
    end

    def author_is_maintainer?
      [:maintain, :admin].include?(action_or_role_level)
    end

    def author_term_and_verb
      if current_user_is_author?
        "You are"
      else
        "This user is"
      end
    end

    def title
      "#{author_term_and_verb} a #{role_name.downcase} on this repository."
    end
  end
end
