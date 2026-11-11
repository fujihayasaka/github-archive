# typed: true
# frozen_string_literal: true

module Conduit
  module EventAdapter
    class PushEvent < Conduit::StratocasterEventAdapter
      include GitHub::Memoizer

      MAX_COMMITS_TO_SHOW = 2

      def title
        T.bind(self, T.untyped)
        description
      end

      def html_url
        push.permalink
      end

      def url
        html_url
      end

      def partial_path
        "events/push"
      end

      def repo_nwo
        repository.name_with_display_owner
      end

      def no_commits
        commit_count.zero?
      end

      def commits
        commit_views
      end

      def ref_name
        ref.to_s.sub(%r{refs/(remotes|heads|tags)/}, "")
      end

      memoize def shas
        push.commits_summary
      end

      memoize def commit_views
        T.bind(self, T.untyped)
        visible_commits.map do |commits_hash|
          Events::PushView::CommitView.from(self, commits_hash)
        end
      end

      def visible_commits
        (commits_hashes || []).take(MAX_COMMITS_TO_SHOW)
      end

      def pusher_is_only_committer
        return if pusher_is_a_deploy_key?
        return unless commit_views.present?

        all = commit_views.all? { |commit| commit.user_login == pusher.display_login }
        "pusher-is-only-committer" if all
      end

      def commit_author_for_email(email)
        @commit_authors_by_email ||= {}
        return @commit_authors_by_email[email] if @commit_authors_by_email[email]
        return unless commit_author_emails.include?(email)

        @commit_authors_by_email[email] = User.find_by_email(email)
      end

      def commit_author_emails
        return [] unless visible_commits.present?

        @commit_author_emails ||= visible_commits
          .filter_map { |commit_hash| commit_hash.dig(:author, :email)&.downcase&.presence }
          .uniq
      end

      def more_commits?
        remaining_commit_count.positive?
      end

      def icon
        "repo-push"
      end

      def remaining_commit_count
        commit_count - MAX_COMMITS_TO_SHOW
      end

      def head
        T.bind(self, T.untyped)
        push.after
      end

      private

      memoize def commits_hashes
        T.bind(self, T.untyped)
        shas.map { |sha| commit_hash_from_sha(sha) }
      end

      memoize def pusher_is_a_deploy_key?
        T.bind(self, T.untyped)
        pusher_type == :deploy_key
      end

      memoize def pusher
        push.pusher
      end

      def commit_count
        push.total_commits_count
      end

      def push
        T.bind(self, T.untyped)
        subject
      end

      def repository
        T.bind(self, T.untyped)
        push.repository
      end

      def ref
        push.ref
      end

      def commit_hash_from_sha(sha)
        id, email, message, name, is_distinctive = sha
        {
          sha: id,
          author: { email:, name: },
          message: message,
          distinct: is_distinctive,
          url: "#{repository.permalink}/commits/#{id}",
        }
      end
    end
  end
end
