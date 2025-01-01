# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class RepositoryStack < Platform::Objects::Base
      include OcticonsHelper

      description "A stack defined on a repository."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, stack)
        stack.async_repository.then do |repo|
          result = permission.typed_can_access?("Repository", repo)
        end
      end

      visibility :internal

      implements_node templates: [[:rs, :repo_id, :repository_stack_id]],  as: "RS", ready_date: "1970-01-01" do |repository_stack|
        {
          prefix: :rs,
          repo_id: repository_stack.repository_id,
          repository_stack_id: repository_stack.id,
        }
      end

      minimum_accepted_scopes ["public_repo"]

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, stack)
        stack.async_repository.then do |repo|
          repo.async_organization.then do |_org|
            permission.belongs_to_repository(stack)
          end
        end
      end

      database_id_field(visibility: :internal)

      field :name, String, "The name of the stack.", null: false
      field :slug, String, "The stack's slug.", null: true
      field :description, String, "The description of the stack.", null: true
      field :featured, Boolean, "Is the stack featured on the marketplace?", null: false
      field :icon_name, String, "The name of the icon to display.", null: true
      field :icon_color, String, "The color to display the stack's icon.", null: true
      field :color, String, "The color to display with the stack.", null: true
      field :security_email, String, "Internal GitHub use only. Email contact for getting in touch with the stack's owner.", null: false, visibility: :internal
      field :is_listed, Boolean, description: "Is the stack listed on the Marketplace?", method: :listed?, null: false
      field :has_verified_owner, Boolean, description: "Is the owner of this stack verified?", method: :verified_owner?, null: false
      field :repository, Objects::Repository, "The repository that owns the stack.", method: :async_repository, null: false

      url_fields description: "The HTTP URL for the Repository Stack." do |stack|
        stack.repository.permalink(include_host: false)
      end
    end
  end
end
