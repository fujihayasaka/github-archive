# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Comparison < Platform::Objects::Base
      description "Represents a comparison between two commit revisions."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        Promise.all([
          permission.async_owner_if_org(object.base_repo),
          permission.async_owner_if_org(object.head_repo),
        ]).then do |base_org, head_org|
          permission.access_allowed?(
            :compare_commits,
            resource: object.base_repo,
            current_org: base_org,
            current_repo: object.base_repo,
            ref_name: object.base,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          ) && permission.access_allowed?(
            :compare_commits,
            resource: object.head_repo,
            current_org: head_org,
            current_repo: object.head_repo,
            ref_name: object.head,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        Promise.all([
          permission.typed_can_see?("Repository", object.head_repo),
          permission.typed_can_see?("Repository", object.base_repo),
        ]).then do |can_see_head, can_see_base|
          can_see_head && can_see_base
        end
      end

      minimum_accepted_scopes ["repo"]

      implements_node templates: [
        [:rcomp, :repo_id, :base_repo_id, :head_repo_id, :base_revision, :head_revision]
      ], as: "RCOMP", uses_database_id: false, ready_date: "1970-01-01" do |comparison|
        Promise.all([comparison.async_compare_repository, comparison.async_head_repo, comparison.async_base_repo]).then do |repo, head_repo, base_repo|
          {
            prefix: :rcomp,
            repo_id: repo.id,
            head_repo_id: head_repo.id,
            base_repo_id: base_repo.id,
            base_revision: comparison.base_revision,
            head_revision: comparison.head_revision,
          }
        end
      end

      field :commits, Connections::ComparisonCommit, max_page_size: 250, description: "The commits which compose this comparison.", null: false, connection: true

      def commits
        @object.async_commits.then do |commits|
          ArrayWrapper.new(commits)
        end
      end

      field :ahead_by, Integer, description: "The number of commits ahead of the base branch.", null: false
      field :behind_by, Integer, description: "The number of commits behind the base branch.", null: false
      field :status, Enums::ComparisonStatus, description: "The status of this comparison.", null: false

      field :base_target, Interfaces::GitObject, description: "The base revision of this comparison.", null: false

      def base_target
        Promise.all([@object.async_base_repo, @object.async_base_oid]).then do |repo, oid|
          Platform::Loaders::GitObject.load(repo, oid)
        end
      end

      field :head_target, Interfaces::GitObject, description: "The head revision of this comparison.", null: false

      def head_target
        Promise.all([@object.async_head_repo, @object.async_head_oid]).then do |repo, oid|
          Platform::Loaders::GitObject.load(repo, oid)
        end
      end

      def self.load_from_global_id(id)
        GitHub::Comparison.load_from_global_id(id, security_violation_behaviour: :nil)
      end

      def self.load_from_next_global_id(parsed_id)
        parts = [parsed_id.parts[:repo_id], parsed_id.parts[:base_repo_id], parsed_id.parts[:head_repo_id], parsed_id.parts[:base_revision], parsed_id.parts[:head_revision]]
        GitHub::Comparison.load_from_global_id(parts.join(":"), security_violation_behaviour: :nil)
      end
    end
  end
end
