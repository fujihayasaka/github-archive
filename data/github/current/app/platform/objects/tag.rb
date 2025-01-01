# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Tag < Platform::Objects::Base
      description "Represents a Git tag."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, tag)
        repo = tag.repository
        permission.async_owner_if_org(repo).then do |org|
          permission.access_allowed?(:get_tag, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_git_object(object)
      end

      scopeless_tokens_as_minimum

      implements_node templates: [[:t, :repo_id, :oid]], as: "TA", ready_date: Platform::Helpers::GlobalId::COHORT_2, uses_database_id: false do |tag|
        {
          prefix: :t,
          repo_id: tag.repository.id,
          oid: tag.oid,
        }
      end

      implements Interfaces::GitObject

      # Overrides Interfaces::GitObject's implementation. Annotated tag objects
      # have their own oids which do not match their commit (target) oid.
      # Build the commitUrl using `tag.target.oid` instead of `tag.oid`
      url_fields prefix: "commit", description: "The HTTP URL for this Git object" do |obj|
        template = Addressable::Template.new("/{owner}/{name}/commit/{oid}")
        template.expand owner: obj.repository.owner.display_login, name: obj.repository.name, oid: obj.target.oid
      end

      field :name, String, "The Git tag name.", null: false

      field :message, String, "The Git tag message.", null: true

      field :target, Interfaces::GitObject, "The Git object the tag points to.", null: false

      field :tagger, Objects::GitActor, "Details about the tag author.", method: :author_actor, null: true

      field :signature, Interfaces::GitSignature, "Tag signing information, if present.", null: true, visibility: :internal

      def signature
        Loaders::GitSignature.load(@object)
      end

      def self.load_from_next_global_id(parsed_id)
        Interfaces::GitObject.load_from_next_global_id(parsed_id)
      end

      def self.load_from_global_id(id)
        Interfaces::GitObject.load_from_global_id(id)
      end
    end
  end
end
