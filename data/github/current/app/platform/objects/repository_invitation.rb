# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class RepositoryInvitation < Platform::Objects::Base
      description "An invitation for a user to be added to a repository."

      implements_node templates: [[:ri, :repo_id, :id]], as: "RI", ready_date: "2021-07-01" do |repository_invitation|
        repository_invitation.async_repository.then do |repo|
          {
            prefix: :ri,
            repo_id: repo.id,
            id: repository_invitation.id,
          }
        end
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, repository_invitation)
        permission.async_repo_and_org_owner(repository_invitation).then do |repo, org|
          permission.access_allowed? :v4_get_repository_invitation,
            resource: repository_invitation,
            current_org: org,
            current_repo: repo,
            forbids: permission.viewer_has_limited_repo_access?(repo, org),
            allow_integrations: true,
            allow_user_via_granular_actor: true
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        return true if permission.viewer&.site_admin? # staff can view invites in stafftools

        object.async_repository.then do |repo|
          next true if object.readable_by?(permission.viewer)

          repo.async_owner.then do |owner|
            next false unless owner.is_a?(::Organization)

            owner.async_business.then do |business|
              business&.owner?(permission.viewer)
            end
          end
        end
      end

      minimum_accepted_scopes ["public_repo", "repo:invite"]

      # can be nullable in the case of a private repo, where the invitee has
      # not yet accepted, or has improper scopes
      field :repository, Interfaces::RepositoryInfo, description: "The Repository the user is invited to.", null: true

      def repository
        Loaders::ActiveRecord.load(::Repository, @object.repository_id,
          # we expose a restricted set of attributes from the repository
          # in repository invitations. in this case, we need to load the repo
          # even though the viewer will not have access to it:
          security_violation_behaviour: :allow
        )
      end

      field :invitee, Objects::User, method: :async_invitee, description: "The user who received the invitation.", null: true

      field :email, String, description: "The email address that received the invitation.", null: true

      field :inviter, Objects::User, method: :async_inviter, description: "The user who created the invitation.", null: false

      field :permalink, Scalars::URI, description: "The permalink for this repository invitation.", null: false

      def permalink
        @object.async_repository.then do
          Addressable::URI.parse(@object.permalink)
        end
      end

      field :permission, Enums::RepositoryPermission, "The permission granted on this repository by this invitation.", null: false

      def permission
        @object.async_role.then do |role|
          if role.present?
            role.async_base_role.then do |base_role|
              base_role.name
            end
          else
            @object.permission_string
          end
        end
      end
    end
  end
end
