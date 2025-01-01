# typed: true
# frozen_string_literal: true

module Commits
  class AttributionInfoComponent < ApplicationComponent
    attr_reader :commit, :repository, :include_verbs, :include_pusher

    def initialize(commit:, repository:, include_verbs: true, include_pusher: false)
      @commit = commit
      @repository = repository
      @include_verbs = include_verbs
      @include_pusher = include_pusher
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

    def show_push_attribution?
      commit&.repository&.feature_flag_enabled?(:show_pusher_on_commit_detail, default: false) && include_pusher && pusher.present?
    end

    def pusher_is_committer?
      if author_actors.count == 1 && pusher
        author_actor = author_actors.first.async_user.sync
        return false unless author_actor
        return author_actor.id == pusher.id
      end
      false
    end

    def push_date_is_close_to_commit_date?
      commit_push&.pushed_at && (commit_push.pushed_at - commit.committer_actor.time < 1.minute)
    end

    def pusher
      commit_push&.pusher
    end

    def pushed_at
      if commit_push.present?
        time_ago_in_words_js commit_push.pushed_at
      else
        nil
      end
    end

    memoize private def commit_push
      Repositories.domain.pushes.by_commit(
        repository_id: commit.repository.id,
        repository_network_id: commit.repository.network_id,
        oid: commit.oid)
    end
  end
end
