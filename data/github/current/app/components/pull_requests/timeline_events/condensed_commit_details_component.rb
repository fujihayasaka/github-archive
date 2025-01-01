# typed: true
# frozen_string_literal: true

module PullRequests::TimelineEvents
  class CondensedCommitDetailsComponent < ApplicationComponent
    include ::TextHelper

    attr_reader :commit, :pull_request, :repository

    def initialize(commit:, pull_request:)
      @commit = commit
      @repository = pull_request.repository
      @pull_request = pull_request
    end

    memoize def commit_permalink
      "/#{repository.name_with_display_owner}/pull/#{pull_request.number}/commits/#{commit.oid}"
    end

    memoize def commit_comments_url
      "/#{repository.name_with_display_owner}/commit/#{commit.oid}#comments"
    end

    def commit_message
      commit.async_short_message_html.sync
    end

    def status_data_channel
      live_update_view_channel(GitHub::WebSocket::Channels.commit(repository, commit.oid))
    end

    def status_live_update_url
      pull_request_commit_status_icon_partial_path(repository.owner_display_login, repository, pull_request.number, oid: commit.oid)
    end

    def commit_message_html
      commit_message_markdown(commit_message)
    end

    def commit_message_classes
      "Link--secondary markdown-title"
    end

    memoize def check_statuses_rollups_path
      "/#{repository.owner_display_login}/#{repository.name}/commits/checks-statuses-rollups"
    end
  end
end
