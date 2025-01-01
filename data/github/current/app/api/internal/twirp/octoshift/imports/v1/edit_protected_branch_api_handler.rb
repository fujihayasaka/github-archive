# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handler for the MonolithTwirp::Octoshift::Imports::V1::EditProtectedBranchAPIService
      class EditProtectedBranchAPIHandler < Api::Internal::Twirp::Handler
        include Platform::Mutations::Shared::ModifyBranchProtectionRule
        include Imports::Helpers::ErrorHandler
        include Imports::Helpers::ModelDelay
        include Imports::Helpers::LiveMigrations
        include Imports::Helpers::ContentCreation

        allow_access_for :client, allowed_clients: %w[octoshift elm migrations_vnext]
        handles_service MonolithTwirp::Octoshift::Imports::V1::EditProtectedBranchAPIService

        # Public: Implementation of the EditProtectedBranch Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::EditProtectedBranchRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::EditProtectedBranchResponse, or a Twirp::Error.
        def edit_protected_branch(req, env)
          check_model_replication_delay!(ProtectedBranch)

          err = validate(req.id, req.action, req.updated_at)
          return err if err

          protected_branch = ProtectedBranch.find_by(id: req.id)
          return Twirp::Error.not_found("Protected branch with id #{req.id} not found") unless protected_branch

          err = check_outdated_updated_at(protected_branch, req.updated_at)
          return err if err

          rate_limited_mode(protected_branch) do
            case req.action
            when :LIVE_MIGRATION_ACTION_EDITED
              edit(protected_branch, req)
            when :LIVE_MIGRATION_ACTION_DELETED
              protected_branch.destroy!

              {}
            else
              Twirp::Error.invalid_argument("must be a valid enum", argument: "action")
            end
          end
        rescue Errors::UnableToEditError => error
          error.message
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        private

        def validate(id, action, updated_at)
          if id <= 0
            return Twirp::Error.invalid_argument("must be positive integer", argument: "id")
          end

          if updated_at.blank?
            return Twirp::Error.invalid_argument("must be present", argument: "updated_at")
          end

          if action == :LIVE_MIGRATION_ACTION_INVALID
            Twirp::Error.invalid_argument("must be a valid enum", argument: "action")
          end
        end

        def edit(protected_branch, req)
          update_branch_protection_rule(protected_branch, {
            requires_approving_reviews: req.requires_approving_reviews&.value,
            required_approving_review_count: req.required_approving_review_count&.value,
            requires_commit_signatures: req.requires_commit_signatures&.value,
            requires_linear_history: req.requires_linear_history&.value,
            allows_force_pushes: req.allows_force_pushes&.value,
            allows_deletions: req.allows_deletions&.value,
            is_admin_enforced: req.is_admin_enforced&.value,
            requires_status_checks: req.requires_status_checks&.value,
            requires_strict_status_checks: req.requires_strict_status_checks&.value,
            requires_code_owner_reviews: req.requires_code_owner_reviews&.value,
            dismisses_stale_reviews: req.dismisses_stale_reviews&.value,
            restricts_review_dismissals: req.restricts_review_dismissals&.value,
            restricts_pushes: req.restricts_pushes&.value,
            required_status_check_contexts: req.required_status_check_contexts.to_a,
            requires_conversation_resolution: req.requires_review_thread_resolution&.value,
            require_last_push_approval: req.require_last_push_approval&.value
          }, {}, entry_point: :edit_protected_branch_api_handler)

          {}
        end
      end
    end
  end
end
