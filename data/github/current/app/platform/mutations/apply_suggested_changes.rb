# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ApplySuggestedChanges < Platform::Mutations::Base
      description "Applies a set of suggested changes to files"

      visibility :internal

      minimum_accepted_scopes ["public_repo"]


      argument :pull_request_id, ID, "The node id of the PullRequest to apply suggestions to.", required: true, loads: Objects::PullRequest
      argument :currentOID, Scalars::GitObjectID, "The OID of the pull request's head ref that the changes should be applied to.", required: true,
        as: :current_oid # This camelization is different than the expected `currentOid` for legacy reasons
      argument :changes, [Inputs::SuggestedChange], "The data being submitted for these suggested changes.", required: true
      argument :message, String, "The suggested change commit message.", required: false

      # Even if this mutation becomes public, this argument should never be user-controlled.
      argument :sign, Boolean, "Whether to try signing the commit.", required: false, default_value: false, visibility: :internal

      def self.async_api_can_modify?(permission, **inputs)
        permission.hidden_from_public?(self)
      end

      def resolve(**inputs)
        unless inputs[:pull_request].suggested_change_applicable_by?(context[:viewer])
          raise Errors::Forbidden.new("You don't have permission to apply suggestions on this pull request.")
        end

        review_comment_promises = inputs[:changes].map do |change|
          Platform::Helpers::NodeIdentification.async_typed_object_from_id([Objects::PullRequestReviewComment], change[:comment_id], context).then do |comment|
            comment.async_pull_request.then do |pull|
              raise Errors::Unprocessable.new("Applying suggestions on multiple pull requests is not supported.") unless pull.id == inputs[:pull_request].id
              comment
            end
          end
        end

        review_comments_map = Promise.all(review_comment_promises).sync.index_by do |c| # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          c.global_relay_id
        end

        changes = []
        inputs[:changes].each do |change|
          changes << {
            path: change[:path],
            suggestion: change[:suggestion],
            comment: review_comments_map[change[:comment_id]],
          }
        end

        inputs.merge!(
          changes: changes,
          viewer: context[:viewer],
          remote_ip: context[:rails_request].remote_ip,
          user_agent: context[:rails_request].user_agent,
        )
        PullRequestReviewComment::ApplySuggestedChange.call(inputs)
      rescue PullRequestReviewComment::ApplySuggestedChange::NotFoundError => e
        raise Errors::NotFound.new(e.message)
      rescue PullRequestReviewComment::ApplySuggestedChange::ForbiddenError => e
        raise Errors::Forbidden.new(e.message)
      rescue PullRequestReviewComment::ApplySuggestedChange::UnprocessableError => e
        raise Errors::Unprocessable.new(e.message)
      end
    end
  end
end
