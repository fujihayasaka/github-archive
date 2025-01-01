# typed: strict
# frozen_string_literal: true

module PullRequests::PageData
  module BannersLoaders
    class PausedDependabotUpdateLoader
      extend T::Sig
      include GitHub::Memoizer

      sig { returns(T::Hash[Symbol, T::Boolean]) }
      attr_reader :to_render

      sig do
        params(current_user: T.nilable(User), pull_request: PullRequest).returns(T::Hash[Symbol, T::Boolean])
      end
      def self.build(current_user:, pull_request:)
        automated_security_updates = new(current_user:, pull_request:)
        automated_security_updates.determine_render
        automated_security_updates.to_render
      end

      sig { params(current_user: T.nilable(User), pull_request: PullRequest).void }
      def initialize(current_user:, pull_request:)
        @current_user = current_user
        @pull_request = pull_request

        @to_render = T.let({ render: false }, T::Hash[Symbol, T::Boolean])
      end

      sig { void }
      def determine_render
        return unless @pull_request.open?
        return unless pull_author_is_dependabot?
        return unless writable?

        @to_render = { render: true } if @pull_request.repository&.dependabot_updates_paused?
      end

      sig { returns(T::Boolean) }
      def pull_author_is_dependabot?
        @pull_request.user == GitHub.dependabot_github_app_bot
      end

      sig { returns(T::Boolean) }
      def writable?
        return true unless GitHub.flipper[:dependabot_paused_write_access_check].enabled?

        @pull_request.repository&.writable_by?(@current_user)
      end
    end
  end
end
