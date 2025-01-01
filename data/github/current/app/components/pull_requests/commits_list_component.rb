# typed: true
# frozen_string_literal: true

module PullRequests
  class CommitsListComponent < ApplicationComponent
    attr_reader :pull_request, :repository, :current_user, :commits

    def initialize(pull_request:, current_user:)
      @pull_request = pull_request
      @repository = pull_request.repository
      @current_user = current_user

      preload_commits
    end

    def show_missing_commits_message?
      pull_request.closed? && !pull_request.merged? && commits.count == 0
    end

    def websocket_channel
      GitHub::WebSocket::Channels.pull_request(pull_request)
    end

    memoize def grouped_commits
      zone = current_user&.time_zone || Time.zone

      commits.group_by do |commit|
        commit.committed_date.in_time_zone(zone).to_date
      end.sort
    end

    memoize def comment_counts_by_oid
      repository.commit_comments.where(commit_id: commits.map(&:oid)).group(:commit_id).count
    end

    def preload_commits
      commits = pull_request.changed_commits

      Promise.all(
        commits.map do |commit|
          promises = [
            commit.author_actors.map { |git_actor| [git_actor.async_visible_actor(current_user), git_actor.async_commits_path_uri] },
            commit.committer_actor.async_visible_actor(current_user),
            commit.committer_actor.async_commits_path_uri,
            commit.async_authored_by_committer?,
            commit.async_short_message_html,
            commit.async_unique_visible_author_actors(current_user).then { |authors| authors.map { |author| author.async_visible_user(current_user) } },
          ]
          unless always_defer_status_loading?
            promises.push(commit.async_has_status_check_rollup?)
          end
          promises.flatten
        end.flatten
      ).sync

      @commits = commits
    end

    def always_defer_status_loading?
      GitHub.flipper[:always_defer_status_loading].enabled?(pull_request.repository)
    end
  end
end
