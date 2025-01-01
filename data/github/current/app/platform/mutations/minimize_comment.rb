# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class MinimizeComment < Platform::Mutations::Base
      description "Minimizes a comment on an Issue, Commit, Pull Request, or Gist"

      visibility :public

      minimum_accepted_scopes %w[repo gist]

      argument :subject_id, ID, "The Node ID of the subject to modify.", required: true, loads: Interfaces::Minimizable, as: :comment
      argument :reason, String, "The reason the comment was minimized", required: false, visibility: :internal
      argument :classifier, Enums::ReportedContentClassifiers, "The classification of comment", required: true

      argument :is_staff_actor, Boolean, "Whether or not the comment was minimized through stafftools.", visibility: :internal, default_value: false, required: false

      field :minimized_comment, Interfaces::Minimizable, "The comment that was minimized.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, comment:, **inputs)
        if comment.is_a?(::GistComment)
          permission.access_allowed?(:minimize_gist_comment, resource: comment, current_org: nil, current_repo: nil, allow_integrations: false, allow_user_via_granular_actor: false)
        elsif comment.is_a?(::DiscussionComment)
          comment.async_discussion.then do |discussion|
            permission.async_repo_and_org_owner(comment).then do |repo, org|
              permission.access_allowed?(:minimize_discussion, repo: repo, resource: discussion, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
            end
          end
        else
          permission.load_repo_and_owner(comment).then do |repo|
            permission.access_allowed?(:minimize_repo_comment, repo: repo, resource: comment, current_org: nil, allow_integrations: true, allow_user_via_granular_actor: true)
          end
        end
      end

      def resolve(comment:, **inputs)
        unless comment.async_minimizable_by?(context[:viewer]).sync
          raise Errors::Forbidden.new("Viewer not authorized")
        end

        comment_author = comment.user || User.ghost

        if comment.set_minimized(context[:viewer], inputs[:reason], inputs[:classifier], comment_author, inputs[:is_staff_actor])
          { minimized_comment: comment }
        else
          raise Errors::Unprocessable.new("Could not minimize comment.")
        end
      end
    end
  end
end
