# typed: true
# frozen_string_literal: true

module PullRequests::TimelineEvents
  class CommitStatusIconComponent < ApplicationComponent
    include ::TextHelper

    attr_reader :commit, :pull_request, :repository, :status_check_rollup

    def initialize(commit:, pull_request:)
      @commit = commit
      @repository = pull_request.repository
      @pull_request = pull_request
      @status_check_rollup = commit.status_check_rollup
    end

    def render?
      @status_check_rollup.present?
    end

    def data_channel
      live_update_view_channel(GitHub::WebSocket::Channels.commit(repository, commit.oid))
    end

    def live_update_url
      pull_request_commit_status_icon_partial_path(repository.owner, repository, pull_request.number, oid: commit.oid)
    end
  end
end
