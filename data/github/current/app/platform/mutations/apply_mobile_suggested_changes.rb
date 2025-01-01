# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ApplyMobileSuggestedChanges < Platform::Mutations::Base
      description "Applies a set of suggested changes to files"
      required_capabilities [:mobile_only_schema_mask]
      minimum_accepted_scopes ["public_repo"]

      argument :pull_request_id, ID, "The node id of the PullRequest to apply suggestions to.", required: true, loads: Objects::PullRequest
      argument :currentOID, Scalars::GitObjectID, "The OID of the pull request's head ref that the changes should be applied to.", required: true,
        as: :current_oid # This camelization is different than the expected `currentOid` for legacy reasons
      argument :changes, [Inputs::MobileSuggestedChangeInput], "The data being submitted for these suggested changes.", required: true
      argument :message, String, "The suggested change commit message.", required: false

      # Even if this mutation becomes public, this argument should never be user-controlled.
      argument :sign, Boolean, "Whether to try signing the commit.", required: false, default_value: true


      field :success, Boolean, "Returns if the suggestion was successfully applied.", null: true

      def self.async_api_can_modify?(permission, pull_request:, **inputs)
        permission.async_repo_and_org_owner(pull_request).then do |repo, org|
          permission.access_allowed?(
            :update_pull_request,
            repo: repo,
            current_org: org,
            resource: pull_request,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          )
        end
      end

      def resolve(**inputs)
        unless inputs[:pull_request].suggested_change_applicable_by?(context[:viewer])
          raise Errors::Forbidden.new("You don't have permission to apply suggestions on this pull request.")
        end

        changes_promises = inputs[:changes].map do |change|
          Platform::Helpers::NodeIdentification.async_typed_object_from_id([Objects::PullRequestReviewComment], change[:comment_id], context).then do |comment|
            comment.async_pull_request.then do |pull|
              raise Errors::Unprocessable.new("Applying suggestions on multiple pull requests is not supported.") unless pull.id == inputs[:pull_request].id

              Platform::Helpers::NodeIdentification.async_typed_object_from_id([Objects::MobileSuggestedChange], change[:suggested_change_id], context).then do |suggested_change|
                {
                  path: suggested_change.path,
                  suggestion: suggested_change.suggestion,
                  comment: comment,
                }
              end
            end
          end
        end

        inputs.merge!(
          changes: changes_promises.map(&:sync), # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          viewer: context[:viewer],
          remote_ip: context[:ip],
          user_agent: context[:user_agent].to_s,
        )
        PullRequestReviewComment::ApplySuggestedChange.call(inputs)

        { success: true }
      rescue PullRequestReviewComment::ApplySuggestedChange::NotFoundError => e
        raise Errors::NotFound.new(e.message)
      rescue PullRequestReviewComment::ApplySuggestedChange::ForbiddenError => e
        raise Errors::Forbidden.new(e.message)
      rescue PullRequestReviewComment::ApplySuggestedChange::UnprocessableError => e
        raise Errors::Unprocessable.new(e.message)
      rescue Git::Ref::WorkflowUpdatePolicyError => e
        raise Errors::Forbidden.new(e.message)
      end
    end
  end
end
