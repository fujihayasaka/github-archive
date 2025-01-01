# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ProvideCopilotCodeReviewFeedback < Platform::Mutations::Base
      description "Provides positive or negative feedback on a Copilot Code Review comment."
      minimum_accepted_scopes ["public_repo"]

      required_capabilities [:mobile_only_schema_mask]

      argument :comment_id, ID, "ID of the pull request comment to provide feedback for.", required: true, loads: Objects::PullRequestReviewComment, as: :comment
      argument :feedback, Enums::CopilotCodeReviewFeedbackType, "Feedback to provide for the comment.", required: true
      argument :feedback_choice, [Enums::CopilotCodeReviewFeedbackOption], "Feedback choice to provide for the comment.", required: false
      argument :text_response, String, "Text response to provide for the comment.", required: false

      field :comment, Objects::PullRequestReviewComment, "Comment to which feedback was provided for.", null: true

      error_fields

      extras [:execution_errors]

      def resolve(comment:, execution_errors:, **inputs)
        feedback = inputs[:feedback]
        feedback_choice = inputs[:feedback_choice]
        text_response = inputs[:text_response]

        comment.async_pull_request.then do |pull_request|
          pull_request.async_repository.then do |repository|
            repository.async_organization.then do |org|
              PullRequests::Copilot::instrument_code_review_feedback(
                request_id: GitHub.context[:request_id],
                organization_id: org&.id,
                repository_id: repository.id,
                pull_request_id: pull_request.id,
                comment_id: comment.id.to_s,
                analytics_tracking_id: nil,
                feedback: feedback,
                feedback_choice: feedback_choice,
                text_response: text_response
              )

              { errors: [] }
            end
          end
        end
      end

      def self.async_api_can_modify?(permission, comment:, **inputs)
        comment.async_pull_request.then do |pull|
          permission.async_repo_and_org_owner(pull).then do |repo, org|
            permission.access_allowed?(
              :copilot_code_review_feedback_writer,
              resource: permission.viewer,
              repo: repo,
              current_org: org,
              allow_integrations: false,
              allow_user_via_granular_actor: true
            )
          end
        end
      end
    end
  end
end
