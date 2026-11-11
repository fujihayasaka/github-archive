# typed: strict
# frozen_string_literal: true

module Businesses
  module AiControls
    module Concerns
      module SourceRepoTreeReader
        extend ActiveSupport::Concern
        extend T::Helpers

        requires_ancestor { Businesses::BusinessController }

        # Resolved repository context passed to the block that processes entries.
        class RepoContext < T::Struct
          const :repo, Repository
          const :owner, String
          const :name, String
          const :oid, String
        end

        # Resolves the enterprise source repository and default branch OID, then
        # yields a RepoContext so callers can list and process tree entries.
        # Returns [] if the repo is missing, inactive, or has no valid default branch.
        # Handles GitRPC and general errors with appropriate logging.
        sig do
          params(
            resource_label: String,
            block: T.proc.params(ctx: RepoContext).returns(T::Array[T::Hash[String, T.untyped]])
          ).returns(T::Array[T::Hash[String, T.untyped]])
        end
        def with_source_repo_tree(resource_label, &block)
          source_repo_id = this_business.subagent_definitions_source_repository_id
          repo = source_repo_id.present? ? Repositories::Public.find_active(source_repo_id) : nil

          return [] if repo.nil?

          begin
            owner = repo.owner_display_login
            name = repo.name

            default_branch_name = repo.default_branch
            return [] if default_branch_name.blank?

            default_branch = repo.heads.find(default_branch_name)
            return [] if default_branch.nil?

            oid = default_branch.target_oid
            return [] unless GitRPC::Util.valid_full_oid?(oid)

            ctx = RepoContext.new(repo: repo, owner: owner, name: name, oid: oid)
            block.call(ctx)
          rescue StandardError => e
            GitHub.logger.warn(
              "Error fetching #{resource_label} data",
              "gh.repo.id": repo.id,
              "error.message": e.message,
              "error.class": e.class.name,
            )
            []
          end
        end
      end
    end
  end
end
