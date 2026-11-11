# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CommitComment < Platform::Objects::Base
      description "Represents a comment on a given Commit."

      implements_node templates: [[:rcc, :repo_id, :commit_comment_id]], as: "CC", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |commit_comment|
        {
          prefix: :rcc,
          repo_id: commit_comment.repository_id,
          commit_comment_id: commit_comment.id
        }
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, commit_comment)
        permission.async_repo_and_org_owner(commit_comment).then do |repo, org|
          permission.access_allowed?(:v4_get_commit_comment, resource: commit_comment, repo: repo, comment: commit_comment, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        Promise.all([
          permission.belongs_to_repository(object),
          object.async_readable_by?(permission.viewer),
        ]).then(&:all?)
      end

      scopeless_tokens_as_minimum

      implements Interfaces::OrgBlockable
      implements Interfaces::Comment
      implements Interfaces::Deletable
      implements Interfaces::Minimizable
      implements Interfaces::Updatable
      implements Interfaces::UpdatableComment
      implements Interfaces::Reactable
      implements Interfaces::Reportable
      implements Interfaces::AbuseReportable
      implements Interfaces::RepositoryNode

      url_fields description: "The HTTP URL permalink for this commit comment." do |commit_comment|
        commit_comment.async_path_uri
      end

      url_fields \
        prefix: :update,
        visibility: :internal,
        deprecated: {
          start_date: Date.new(2018, 2, 1),
          reason: "Object-specific update endpoints will be removed.",
          superseded_by: nil,
          owner: "xuorig",
        },
        description: "The HTTP URL to the endpoint for updating this commit comment." do |commit_comment|
        commit_comment.async_update_path_uri
      end

      field :commit, Objects::Commit, description: "Identifies the commit associated with the comment, if the commit exists.", null: true

      def commit
        @object.async_repository.then do |repository|
          Loaders::GitObject.load(repository, @object.commit_id, expected_type: :commit)
        end
      end

      field :body, String, "Identifies the comment body.", null: false
      field :body_version, String, visibility: :internal, description: "Identifies the comment body hash.", null: false

      field :path, String, "Identifies the file path associated with the comment.", null: true
      field :position, Integer, "Identifies the line position associated with the comment.", null: true
    end
  end
end
