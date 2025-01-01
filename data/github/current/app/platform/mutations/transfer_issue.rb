# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class TransferIssue < Platform::Mutations::Base
      description "Transfer an issue to a different repository"

      minimum_accepted_scopes ["repo"]

      argument :issue_id, ID, "The Node ID of the issue to be transferred", required: true, loads: Objects::Issue
      argument :repository_id, ID, "The Node ID of the repository the issue should be transferred to", required: true, loads: Objects::Repository
      argument :create_labels_if_missing, Boolean, "Whether to create labels if they don't exist in the target repository (matched by name)", required: false, default_value: false

      field :issue, Objects::Issue, "The issue that was transferred", null: true
      error_fields

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, repository:, issue:, **inputs)
        permission.async_owner_if_org(repository).then do |org|
          permission.access_allowed? :transfer_issue, repo: repository, issue: issue, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true
        end
      end

      def resolve(repository:, issue:, **inputs)
        viewer = context[:viewer]

        transfer = IssueTransfer.new(
          old_issue: issue,
          old_repository: issue.repository,
          new_repository: repository,
          actor: viewer,
        )

        ensure_transfer_valid!(transfer)
        create_labels_if_missing = inputs[:create_labels_if_missing] || false

        begin
          transfer.async_transfer!(create_labels_if_missing: create_labels_if_missing) # domain-isolation-query-violation:ignore:packages/issues (INSERT, UPDATE)
          {
            issue: transfer.new_issue,
            errors: [],
          }
        rescue ActiveRecord::RecordInvalid => error
          raise Platform::Errors::Unprocessable.new(error)
        end
      end

      private

      def ensure_transfer_valid!(transfer)
        transfer.valid?
        validation_errors = transfer.errors

        if validation_errors.include?(:actor)
          actor_errors = validation_errors.full_messages_for(:actor)
          raise Errors::Forbidden.new(actor_errors.first) if actor_errors.any?
        end

        # detect specific validation error types
        data_errors = validation_errors
          .to_hash(true)
          .values_at(:old_issue, :old_repository, :new_repository)
          .compact.join(", ")

        if data_errors.present?
          raise Errors::Unprocessable.new(data_errors)
        end
      end
    end
  end
end
