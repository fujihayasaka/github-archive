# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class RepositoryAdvisoryComment < Platform::Objects::Base
      description "A comment on a repository security advisory"
      mobile_only true
      minimum_accepted_scopes ["public_repo"]

      implements_node(templates: [[:rac, :repository_id, :repository_advisory_id, :id]], as: "RAC", ready_date: "2021-03-18") do |repo_adv_comment|
        repo_adv_comment.async_repository_advisory.then do |repository_advisory|
          {
            prefix: :rac,
            id: repo_adv_comment.id,
            repository_advisory_id: repository_advisory.id,
            repository_id: repository_advisory.repository_id,
          }
        end
      end

      implements Interfaces::Comment
      implements Interfaces::Deletable
      implements Interfaces::MayBeInternal
      implements Interfaces::Reactable
      implements Interfaces::RepositoryNode
      implements Interfaces::UniformResourceLocatable
      implements Interfaces::Updatable
      implements Interfaces::UpdatableComment
      implements Interfaces::OrgBlockable

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, comment)
        # this check is only here for SAML enforcement (side
        # effect of `access_allowed` via `current_org`).
        permission.async_repo_and_org_owner(comment).then do |repo, org|
          permission.access_allowed?(
            :saml_via_graphql, # returns false
            resource: comment,
            current_org: org,
            current_repo: repo,
            allow_integrations: false,
            allow_user_via_granular_actor: false)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, comment)
        comment.async_repository_advisory.then do |advisory|
          permission.typed_can_see?("RepositoryAdvisory", advisory) &&
            comment.readable_by?(permission.viewer)
        end
      end

      database_id_field

      # Interfaces::Comment

      def authored_by_subject_author
        @object.async_repository_advisory.then do |advisory|
          advisory.author_id == @object.user_id
        end
      end

      def subject_type
        "advisory"
      end

      # Interfaces::MayBeInternal

      def is_internal
        object.async_internal?
      end
    end
  end
end
