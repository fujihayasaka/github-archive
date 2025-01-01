# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handles the creation of imported protected branch data.
      class ImportProtectedBranchAPIHandler < Api::Internal::Twirp::Handler
        include Platform
        include Helpers::ErrorHandler
        include Helpers::ModelDelay

        handles_service MonolithTwirp::Octoshift::Imports::V1::ImportProtectedBranchAPIService
        allow_access_for :client, allowed_clients: ["octoshift"]

        CreateMutation = GraphQL.parse <<~'GRAPHQL'
          mutation($input: CreateBranchProtectionRuleInput!) {
            createBranchProtectionRule(input: $input) {
              branchProtectionRule {
                databaseId
              }
            }
          }
        GRAPHQL

        # Public: Implementation of the ImportProtectedBranch Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::ImportProtectedBranchRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::ImportProtectedBranchResponse, or a Twirp::Error.
        def import_protected_branch(req, env)
          check_model_replication_delay!(ProtectedBranch)

          if req.repository_id.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "repository_id")
          end
          if req.name.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "name")
          end

          # Note that we're using Repository and not ImportableRepository. While they should act the
          # same, their global_relay_ids are actually different, so ImportableRepository does not work
          # here in the GraphQL call. Tracked in https://github.com/github/octoshift/issues/1372.
          repository = replica(Repository).find_by(id: req.repository_id)
          unless repository && repository.active?
            return Twirp::Error.not_found("Repository not found.", argument: "repository_id", value: req.repository_id.to_s, octoshift_error_code: "REPOSITORY_DELETED")
          end

          import = repository.import
          unless import
            return Twirp::Error.not_found("Repository is not associated with a valid Import.", argument: "repository_id", value: req.repository_id.to_s)
          end

          return already_exists_error_handler("ProtectedBranch") if replica(ProtectedBranch).query { |k| k.where(name: req.name, repository_id: req.repository_id).exists? }

          result = Platform.execute(CreateMutation,
            target: :public,
            context: { viewer: repository.owner.admins.first },
            variables: {
              input: {
                repositoryId: repository.global_relay_id,
                pattern: req.name,
                requiresApprovingReviews: req.requires_approving_reviews&.value,
                requiredApprovingReviewCount: req.required_approving_review_count&.value,
                requiresCommitSignatures: req.requires_commit_signatures&.value,
                requiresLinearHistory: req.requires_linear_history&.value,
                allowsForcePushes: req.allows_force_pushes&.value,
                allowsDeletions: req.allows_deletions&.value,
                isAdminEnforced: req.is_admin_enforced&.value,
                requiresStatusChecks: req.requires_status_checks&.value,
                requiresStrictStatusChecks: req.requires_strict_status_checks&.value,
                requiresCodeOwnerReviews: req.requires_code_owner_reviews&.value,
                dismissesStaleReviews: req.dismisses_stale_reviews&.value,
                restrictsReviewDismissals: req.restricts_review_dismissals&.value,
                restrictsPushes: req.restricts_pushes&.value,
                requiredStatusCheckContexts: req.required_status_check_contexts.to_a,
                requiresConversationResolution: req.requires_review_thread_resolution&.value,
                requireLastPushApproval: req.require_last_push_approval&.value,
              }
            }
          )

          unless result.errors.empty?
            return Twirp::Error.canceled(
              "Could not create protected branch.",
              octoshfit_error_code: "INVALID_RECORD",
              errors: result.errors.map { |error| error["message"] }.join(", ")
            )
          end

          {
            protected_branch: {
              id: result.data["createBranchProtectionRule"]["branchProtectionRule"]["databaseId"]
            }
          }
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end
      end
    end
  end
end
