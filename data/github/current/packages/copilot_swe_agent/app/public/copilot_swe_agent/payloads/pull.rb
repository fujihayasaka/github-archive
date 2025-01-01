# typed: strict
# frozen_string_literal: true

module CopilotSweAgent
  module Payloads
    class Pull
      include AvatarHelper

      class PullHash < T::Struct
        prop :id, Integer
        prop :number, Integer
        prop :state, T.nilable(Symbol)
        prop :title, String
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
      end

      sig { returns(PullRequest) }
      attr_reader :pull_request

      sig { params(pull_request: PullRequest).void }
      def initialize(pull_request:)
        @pull_request = pull_request
      end

      sig { returns(PullHash) }
      def call
        PullHash.new(
          id: pull_request.id,
          number: pull_request.number,
          state: pull_request.state,
          title: pull_request.title,
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
        )
      end
    end
  end
end
