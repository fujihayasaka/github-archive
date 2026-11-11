# typed: strict
# frozen_string_literal: true

module CopilotSessions
  module Payloads
    class Pull
      include AvatarHelper

      class PullHash < T::Struct
        prop :id, Integer
        prop :global_relay_id, String
        prop :number, Integer
        prop :state, T.nilable(Symbol)
        prop :title, String
        prop :title_html, String
        prop :reviewable_state, String
        prop :url, String
        prop :labels, T::Array[String]
        prop :comments, Integer
        prop :assignees_avatar_urls, T::Array[String]
        prop :created_at, Time
        prop :updated_at, Time
        prop :merged_at, T.nilable(Time)
        prop :closed_at, T.nilable(Time)
        prop :author, String
        prop :head_sha, String
        prop :repository_nwo, T.nilable(String)
        prop :changed_files, Integer
        prop :repository_id, Integer
        prop :head_ref_name, String
        prop :base_ref_name, String
        prop :diffs, T.nilable(T::Array[T.untyped]), default: nil
        prop :aliveChannel, T.nilable(String), default: nil
        prop :body, T.nilable(String), default: nil
        prop :body_html, T.nilable(String), default: nil
        prop :pr_diff_summary, T.nilable(T::Hash[String, Integer]), default: nil
        prop :body_revision_count, T.nilable(Integer), default: nil
        prop :commit_alive_channel, T.nilable(String), default: nil
      end

      sig { returns(PullRequest) }
      attr_reader :pull_request

      sig { params(pull_request: PullRequest, include_body: T::Boolean).void }
      def initialize(pull_request:, include_body: false)
        @pull_request = pull_request
        @include_body = include_body
      end

      sig { returns(PullHash) }
      def call
        changed_files_count = begin
          pull_request.changed_files.to_i
        rescue GitRPC::Error, Rugged::OdbError
          0
        end

        payload = {
          id: pull_request.id,
          global_relay_id: pull_request.global_relay_id,
          number: pull_request.number,
          state: pull_request.state,
          title: pull_request.title,
          title_html: pull_request.title_html,
          reviewable_state: pull_request.reviewable_state,
          url: pull_request.url.to_s,
          labels: pull_request.labels.map(&:name),
          comments: T.must(pull_request.issue).comments.count,
          assignees_avatar_urls: pull_request.assignees.map { |assignee| avatar_url_for(assignee) },
          created_at: pull_request.created_at,
          updated_at: pull_request.updated_at,
          merged_at: pull_request.merged_at,
          closed_at: pull_request.closed_at,
          author: T.must(pull_request.user).display_login,
          head_sha: pull_request.head_sha,
          repository_nwo: pull_request.repository&.name_with_display_owner,
          changed_files: changed_files_count,
          pr_diff_summary: calculate_diff_stats,
          aliveChannel: GitHub::WebSocket::Channels.signed_pull_request(pull_request),
          head_ref_name: pull_request.head_ref_name,
          base_ref_name: pull_request.base_ref_name,
          repository_id: T.must(pull_request.repository).id,
          commit_alive_channel: GitHub::WebSocket::Channels.signed_commit(T.must(pull_request.repository), pull_request.head_sha),
          body_revision_count: T.must(pull_request.issue).user_content_edits.size
        }

        if @include_body
          payload[:body] = pull_request.body
          payload[:body_html] = pull_request.body_html
        end

        PullHash.new(payload)
      end

      private

      sig { returns(T.nilable(T::Hash[String, Integer])) }
      def calculate_diff_stats
        summary_diff = pull_request.historical_comparison.async_diff(summary: true).sync

        {
          "lines_added" => summary_diff.additions,
          "lines_changed" => summary_diff.changes,
          "lines_deleted" => summary_diff.deletions,
        }
      rescue GitRPC::Error => error
        GitHub.logger.warn "Failed to calculate diff stats for PR #{pull_request.id}: #{error.message}"
        Failbot.report(error, pull_request_id: pull_request.id)
        nil
      end
    end
  end
end
