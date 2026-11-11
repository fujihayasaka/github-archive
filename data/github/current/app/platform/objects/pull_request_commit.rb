# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PullRequestCommit < Platform::Objects::Base
      description "Represents a Git commit part of a pull request."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, pr_commit)
        permission.typed_can_access?("Commit", pr_commit.commit)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_pull_request(object)
      end

      scopeless_tokens_as_minimum

      implements_node templates: [[:r, :repo_id, :pull_id, :commit_oid]], as: "PURC", ready_date: Platform::Helpers::GlobalId::COHORT_3, uses_database_id: false do |pr_commit|
        {
          prefix: :r,
          repo_id: pr_commit.pull_request.repository_id,
          pull_id: pr_commit.pull_request.id,
          commit_oid: pr_commit.oid,
        }
      end

      implements Interfaces::UniformResourceLocatable

      field :pull_request, Objects::PullRequest, "The pull request this commit belongs to", null: false

      field :commit, Objects::Commit, "The Git commit object", null: false

      url_fields description: "The HTTP URL for this pull request commit" do |pull_request_commit|
        Promise.all([
          pull_request_commit.pull_request.async_repository,
          pull_request_commit.pull_request.async_issue,
        ]).then do |repository, issue|
          repository.async_owner.then do |owner|
            Addressable::Template.new("/{owner}/{name}/pull/{number}/commits/{oid}").expand(
              owner: owner.display_login,
              name: repository.name,
              number: issue.number,
              oid: pull_request_commit.commit.oid,
            )
          end
        end
      end

      field :message_headline_html_link,
        Scalars::HTML,
        "Link to a pull request commit page using commit's short message as the link text",
        method: :async_message_headline_html_link,
        visibility: :internal,
        null: false

      field :websocket, String, visibility: :internal, description: "The websocket channel ID for live updates.", null: false

      def websocket
        @object.pull_request.async_repository.then do |repository|
          GitHub::WebSocket::Channels.commit(repository, @object.commit.oid)
        end
      end

      def self.load_from_next_global_id(parsed_id)
        Models::PullRequestCommit.load_from_next_global_id(parsed_id)
      end

      def self.load_from_global_id(id)
        Models::PullRequestCommit.load_from_global_id(id)
      end
    end
  end
end
