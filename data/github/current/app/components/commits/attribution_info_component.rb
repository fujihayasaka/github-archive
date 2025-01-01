# typed: true
# frozen_string_literal: true

module Commits
  class AttributionInfoComponent < ApplicationComponent
    attr_reader :commit, :repository, :include_verbs

    def initialize(commit:, repository:, include_verbs: true)
      @commit = commit
      @repository = repository
      @include_verbs = include_verbs
    end

    def inline_author_names
      author_actors.count == 1 || (author_actors.count == 2 && !committed_by_non_author?)
    end

    memoize def author_actors
      commit.author_actors
    end

    memoize def committed_via_web?
      commit.committed_via_web?
    end

    memoize def committed_by_non_author?
      !commit.async_authored_by_committer?.sync && !committed_via_web?
    end

    def last_author_index
      author_actors.count - 1
    end

    def committed_word
      "committed" if include_verbs
    end

    def authored_word
      "authored" if include_verbs
    end

    def authors_word
      if include_verbs
        "people"
      else
        "authors"
      end
    end

    def commit_date
      time_ago_in_words_js commit.committer_actor.time
    end

    def attribution
      authors = commit.async_unique_visible_author_actors(current_user).sync
      authors << commit.committer_actor if committed_by_non_author?

      author_names = authors.map { |author| author.async_visible_user(current_user).sync&.display_login || author.display_name }
      title = html_safe_to_sentence(author_names)
      title += " (non-author committer)" if committed_by_non_author?

      title
    end
  end
end
