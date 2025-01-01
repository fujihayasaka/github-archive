# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateTeamDiscussionComment < Platform::Mutations::Base
      description "Creates a new team discussion comment."

      minimum_accepted_scopes ["write:discussion"]

      argument :discussion_id, ID, "The ID of the discussion to which the comment belongs. This field is required.",
        required: false, loads: Objects::TeamDiscussion, as: :post, deprecated: Helpers::TeamDiscussion::DeprecationNotice
      argument :body, String, "The content of the comment. This field is required.", required: false,
        deprecated: Helpers::TeamDiscussion::DeprecationNotice

      # This field is intentionally marked as :internal. It should not be made public because an API
      # consumer should not need to care about the formatter.
      argument :formatter, Enums::CommentBodyFormatter, "The formatter for the comment body. Defaults to 'MARKDOWN'.",
        visibility: :internal, required: false, deprecated: Helpers::TeamDiscussion::DeprecationNotice

      field :team_discussion_comment, Objects::TeamDiscussionComment, "The new comment.", null: true,
        deprecated: Helpers::TeamDiscussion::DeprecationNotice

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, post:, **inputs)
        # Those 2 arguments are in fact _required_ but we need to mark them as _optional_ since we are deprecating
        # this mutation (by annotating all arguments as deprecated).
        Platform::Helpers::TeamDiscussion.raise_missing_mutation_argument(:body, self) if inputs[:body].nil?

        discussion = post
        discussion.async_organization.then do |org|
          permission.access_allowed?(
            :create_team_discussion_comment,
            resource: discussion,
            organization: org,
            current_repo: nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true)
        end
      end

      def resolve(post:, **inputs)

        comment = post.replies.build(
          body: inputs[:body],
          user: context[:viewer],
          formatter: inputs[:formatter])

        if comment.save
          { team_discussion_comment: comment }
        else
          raise Errors::Validation.new(comment.errors.full_messages.to_sentence)
        end
      end
    end
  end
end
