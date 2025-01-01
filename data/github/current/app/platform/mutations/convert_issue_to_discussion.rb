# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ConvertIssueToDiscussion < Platform::Mutations::Base
      description "Convert an issue to a discussion."

      minimum_accepted_scopes ["public_repo"]

      visibility :internal

      argument :issue_id, ID, "The id of the issue to be converted.",
        required: true,
        loads: Objects::Issue,
        as: :issue

      argument :category_id, ID, "The id of the discussion category to associate with the new discussion.",
        required: true,
        loads: Objects::DiscussionCategory,
        as: :category

      error_fields

      field :discussion, Objects::Discussion, "The discussion that was just created.", null: true

      extras [:execution_errors]

      PATH_TRANSLATION = {
        category: "categoryId",
      }.freeze

      def self.async_api_can_modify?(permission, issue:, category:, **inputs)
        return false if permission.integration_bot_request?

        permission.async_repo_and_org_owner(issue).then do |repo, org|
          action = if category.supports_announcements?
            :create_discussion_announcement
          else
            :create_discussion
          end

          permission.access_allowed?(
            :edit_issue,
            resource: issue,
            repo: repo,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          ) &&
          permission.access_allowed?(
            action,
            repo: repo,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          ) &&
          issue.async_can_be_converted_by?(permission.viewer)
        end
      end

      def resolve(issue:, category:, execution_errors:)
        converter = IssueToDiscussionConverter.new(issue, actor: context[:viewer], category: category)

        unless converter.prepare_for_conversion
          message = "Unable to convert this issue to a discussion. "
          if converter.discussion
            message += converter.discussion.errors.full_messages.to_sentence
          else
            message += issue.errors.full_messages.to_sentence
          end
          raise Errors::Unprocessable.new(message)
        end

        ConvertToDiscussionJob.perform_later(context[:viewer], converter.discussion,
          converter.issue_originally_open)

        {
          discussion: converter.discussion,
          errors: []
        }
      end
    end
  end
end
