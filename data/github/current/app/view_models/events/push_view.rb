# typed: false
# frozen_string_literal: true

# Decorates a Stratocaster::Attributes::Push event with view logic.
#
# Examples
#
#   # equivalent ways to render the event's html
#   render_event(Events::PushView.new(event))
#
#   # or
#   render_event(Events::View.for(event))
module Events
  class PushView < View
    include UrlHelper

    class CommitView
      attr_accessor :push, :sha, :email, :message, :name

      def initialize(push = nil, sha = nil, email = nil, message = nil, name = nil)
        @push    = push
        @sha     = sha
        @email   = email
        @message = message
        @name    = name
      end

      def self.from(push, hash)
        new(push, hash[:sha], hash[:author][:email], hash[:message], hash[:author][:name])
      end

      def user_name
        user || name || "Someone"
      end

      def user_login
        user.display_login if user
      end

      # Lookup the User from the email address they used when committing this
      # code. It's possible that they haven't added this email address to their
      # GitHub account, so we may not be able to find their User object.
      #
      # Returns the User that authored this commit or nil if not found.
      def user
        push.commit_author_for_email(email)
      end

      def repository
        push.repository
      end
    end

    def title_text
      parts = [actor_text, actor_bot_identifier_text, "pushed to", branch_text, "in", repo_text]
      parts.compact.join(" ")
    end

    # Return truthy if the person pushing to the repo is the same person
    # who authored all of the commits in the push.
    #
    # Returns the CSS class String to use in the template.
    def pusher_is_only_committer
      all = commits.all? { |commit_view| commit_view.user_login == actor_login }
      "pusher-is-only-committer" if all
    end

    def ref_name
      ref.to_s.sub(/refs\/(remotes|heads|tags)\//, "")
    end

    def remaining_commit_count
      commit_count - Stratocaster::Event::MAX_COMMITS_TO_SHOW
    end

    def more_commits?
      remaining_commit_count > 0
    end

    def commit_count
      payload[:size].to_i
    end

    def url
      "/#{repo_nwo}/compare/#{before[0, 10]}...#{head[0, 10]}"
    end

    def no_commits
      commit_count == 0
    end

    def commits
      @commit_views ||= visible_commits.reverse.map do |commit_hash|
        CommitView.from(self, commit_hash)
      end
    end

    def head
      payload[:head].to_s
    end

    private

    def branch_text
      if repo_nwo
        ERB::Util.force_escape(ref_name)
      else
        "(deleted)"
      end
    end

    # do not call this
    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def push
      return unless payload[:push_id].present? && payload[:repository_id].present?

      @push ||= unless defined?(@push)
        push = Repositories.domain.pushes.by_id_and_repo_id(id: payload[:push_id], repository_id: payload[:repository_id])

        push
      end
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

    def before
      payload[:before] || push.try(:before).to_s
    end

    def ref
      payload[:ref].to_s
    end
  end
end
