# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Tree < Platform::Objects::Base
      description "Represents a Git tree."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, tree)
        repo = tree.repository
        permission.async_owner_if_org(repo).then do |org|
          permission.access_allowed?(:get_tree, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_git_object(object)
      end

      scopeless_tokens_as_minimum

      implements_node templates: [[:rt, :repo_id, :oid]], as: "TREE", uses_database_id: false, ready_date: Platform::Helpers::GlobalId::COHORT_4 do |tree|
        {
          prefix: :rt,
          repo_id: tree.repository.id,
          oid: tree.oid,
        }
      end

      implements Interfaces::GitObject

      field :entries, [Objects::TreeEntry], description: "A list of tree entries.", null: true

      def self.load_from_next_global_id(parsed_id)
        Interfaces::GitObject.load_from_next_global_id(parsed_id)
      end

      def self.load_from_global_id(id)
        Interfaces::GitObject.load_from_global_id(id)
      end
    end
  end
end
