# typed: true
# frozen_string_literal: true

module Commits
  class ListItemComponent < ApplicationComponent
    include ::TextHelper
    include ResilienceHelper

    CHECK_RUN_UNAVAILABLE = "unavailable"

    attr_reader :commit, :commit_comment_count, :current_blob_path, :pull_request, :turbo_frame, :always_defer_status_loading

    def initialize(commit:, commit_comment_count: nil, current_blob_path: nil, pull_request: nil, turbo_frame: nil, always_defer_status_loading: false)
      @commit = commit
      @commit_comment_count = commit_comment_count || with_database_error_fallback(fallback: 0) { commit.comment_count }
      @current_blob_path = current_blob_path
      @pull_request = pull_request
      @turbo_frame = turbo_frame
      @always_defer_status_loading = always_defer_status_loading
    end

    memoize def repository
      pull_request ? pull_request.repository : commit.repository
    end

    def live_update_url
      helpers.commits_list_item_path(
        user_id: repository.owner_display_login,
        repository: repository.name,
        name: commit.oid,
        pull_request_id: pull_request&.id
      )
    end

    memoize def websocket_channel
      GitHub::WebSocket::Channels.commit(repository, commit.oid)
    end

    memoize def resource_path
      if pull_request
        "/#{repository.owner_display_login}/#{repository.name}/pull/#{pull_request.number}/commits/#{commit.oid}"
      else
        commit.permalink(include_host: false)
      end
    end

    memoize def message_body_html
      commit.async_message_body_html.sync
    end

    def message_headline_html
      commit.async_short_message_html.sync
    end

    memoize def has_status_check_rollup?
      with_database_error_fallback(fallback: CHECK_RUN_UNAVAILABLE) do
        commit.async_has_status_check_rollup?.sync
      end
    end

    alias status_check_rollup_availability has_status_check_rollup?

    memoize def check_statuses_rollups_path
      "/#{repository.owner_display_login}/#{repository.name}/commits/checks-statuses-rollups"
    end

    memoize def comments_path
      "/#{commit.repository.owner_display_login}/#{commit.repository.name}/commit/#{commit.oid}#comments"
    end

    def render_current_blob_path_link?
      current_blob_path.present?
    end

    def sha_label
      "Copy the full SHA"
    end
  end
end
