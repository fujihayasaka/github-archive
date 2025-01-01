# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class UserContentEdit < Platform::Objects::Base
      description "An edit on user content"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        # use the user content this edit is on to determine access
        object.async_user_content.then do |user_content|
          class_name = Platform::Helpers::NodeIdentification.type_name_from_object(user_content)
          permission.typed_can_access?(class_name, user_content)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_user_content.then do |user_content|
          content_type_name = Platform::Helpers::NodeIdentification.type_name_from_object(user_content)
          next false unless permission.typed_can_see?(content_type_name, user_content)

          object.async_viewer_can_read?(permission.viewer)
        end
      end

      scopeless_tokens_as_minimum

      implements_node templates: [
        [:rcce, :repo_id, :commit_comment_id, :id],
        [:rie, :repo_id, :issue_id, :id],
        [:rice, :repo_id, :issue_comment_id, :id],
        [:rprr, :repo_id, :pull_request_review_id, :id],
        [:rprrce, :repo_id, :pull_request_review_comment_id, :id],
        [:rde, :repo_id, :discussion_id, :id],
        [:rdce, :repo_id, :discussion_comment_id, :id],
        [:rrae, :repo_id, :repository_advisory_id, :id],
        [:rrace, :repo_id, :repository_advisory_comment_id, :id],
        [:rgce, :user_id, :gist_id, :id],
        [:ottde, :org_id, :team_id, :team_discussion_id, :id],
        [:ottdce, :org_id, :team_id, :team_discussion_comment_id, :id]], as: "UCE", ready_date: Platform::Helpers::GlobalId::COHORT_3 do |user_content_edit|

        user_content_edit.async_user_content.then do |user_content|
          repo_or_team_promise = if user_content_edit.user_content_type == "DiscussionPost" || user_content_edit.user_content_type == "DiscussionPostReply"
            user_content.async_team
          elsif user_content_edit.user_content_type == "GistComment"
            Promise.resolve(nil)
          elsif user_content.present?
            user_content.async_repository
          else
            Promise.resolve(nil)
          end

          repo_or_team_promise.then do |repo_or_team_or_nil|
            global_id = {
              id: user_content_edit.id
            }

            # Sometimes the `user_content` isn't actually there, just use the foreign key
            user_content_id = user_content_edit.user_content_id

            # If the user content isn't there, we can't get the repository ID, either:
            repo_id_or_team_id = repo_or_team_or_nil&.id || 0

            case user_content_edit.user_content_type
            when "CommitComment"
              global_id.merge!({
                prefix: :rcce,
                commit_comment_id: user_content_id,
                repo_id: repo_id_or_team_id
              })
            when "Issue"
              global_id.merge!({
                prefix: :rie,
                issue_id: user_content_id,
                repo_id: repo_id_or_team_id
              })
            when "IssueComment"
              global_id.merge!({
                prefix: :rice,
                issue_comment_id: user_content_id,
                repo_id: repo_id_or_team_id
              })
            when "PullRequestReview"
              global_id.merge!({
                prefix: :rprr,
                pull_request_review_id: user_content_id,
                repo_id: repo_id_or_team_id
              })
            when "PullRequestReviewComment"
              global_id.merge!({
                prefix: :rprrce,
                pull_request_review_comment_id: user_content_id,
                repo_id: repo_id_or_team_id
              })
            when "Discussion"
              global_id.merge!({
                prefix: :rde,
                discussion_id: user_content_id,
                repo_id: repo_id_or_team_id
              })
            when "DiscussionComment"
              global_id.merge!({
                prefix: :rdce,
                discussion_comment_id: user_content_id,
                repo_id: repo_id_or_team_id
              })
            when "RepositoryAdvisory"
              global_id.merge!({
                prefix: :rrae,
                repository_advisory_id: user_content_id,
                repo_id: repo_id_or_team_id
              })
            when "RepositoryAdvisoryComment"
              global_id.merge!({
                prefix: :rrace,
                repository_advisory_comment_id: user_content_id,
                repo_id: repo_id_or_team_id
              })
            when "GistComment"
              global_id.merge!({
                prefix: :rgce,
                user_id: user_content.user_id,
                gist_id: user_content.gist_id,
              })
            when "DiscussionPost"
              global_id.merge!({
                prefix: :ottde,
                org_id: repo_or_team_or_nil&.organization_id,
                team_id: repo_id_or_team_id,
                team_discussion_id: user_content_id,
              })
            when "DiscussionPostReply"
              global_id.merge!({
                prefix: :ottdce,
                org_id: repo_or_team_or_nil&.organization_id,
                team_id: repo_id_or_team_id,
                team_discussion_comment_id: user_content_id,
              })
            else
              raise(Platform::Errors::NotFound, "UserContentEdit - content type '#{user_content_edit.user_content_type}' does not have a global id template")
            end

            global_id
          end
        end
      end

      created_at_field
      updated_at_field
      deleted_at_field
      field :edited_at, Scalars::DateTime, "When this content was edited", null: false

      field :editor, description: "The actor who edited this content", resolver: Resolvers::ActorEditor
      field :deleted_by, description: "The actor who deleted this content", resolver: Resolvers::ActorDeletedBy
      field :diff, String, "A summary of the changes for this edit", method: :safe_diff, null: true
      field :diff_before, String, "A summary of the changes for the previous edit", method: :safe_diff_before, null: true, visibility: :under_development

      field :first_edit, Boolean, "Returns true if this is the first edit on the content", null: false, method: :first_edit?, visibility: :under_development
      field :newest, Boolean, "Returns true if this is the newest edit on the content", null: false, method: :newest?, visibility: :under_development
      field :viewer_can_delete, Boolean, "Returns true if the viewer can delete this edit", null: false, visibility: :under_development
      def viewer_can_delete
        @object.async_viewer_can_delete?(@context[:viewer])
      end

      def self.load_from_next_global_id(parsed_id)
        prefix = parsed_id.parts[:prefix]
        id = parsed_id.parts[:id]

        edit_object_promise = case prefix
        when :rcce
          Platform::Loaders::ActiveRecord.load(::CommitCommentEdit, id)
        when :rie
          Platform::Loaders::ActiveRecord.load(::IssueEdit, id)
        when :rice
          Platform::Loaders::ActiveRecord.load(::IssueCommentEdit, id)
        when :rprr
          Platform::Loaders::ActiveRecord.load(::PullRequestReviewEdit, id)
        when :rprrce
          Platform::Loaders::ActiveRecord.load(::PullRequestReviewCommentEdit, id)
        when :rde
          Platform::Loaders::ActiveRecord.load(::DiscussionEdit, id)
        when :rdce
          Platform::Loaders::ActiveRecord.load(::DiscussionCommentEdit, id)
        when :rgce, :ottde, :ottdce
          Platform::Loaders::ActiveRecord.load(::UserContentEdit, id)
        when :rrae
          Platform::Loaders::ActiveRecord.load(::RepositoryAdvisoryEdit, id)
        when :rrace
          Platform::Loaders::ActiveRecord.load(::RepositoryAdvisoryCommentEdit, id)
        else
          raise(Platform::Errors::NotFound, "Template prefix '#{prefix}' does not match an existing global id template")
        end

        edit_object_promise.then do |edit_object|
          next edit_object if edit_object.present?

          Platform::Loaders::ActiveRecord.load(::UserContentEdit, id).then do |edit_object|
            # TODO: if this fallback isn't used in production this should be deleted
            GitHub.dogstats.increment("platform.user_content_edit.edit_object_nil", tags: ["class:#{edit_object&.class&.name}"])
            edit_object
          end
        end.then do |edit_object|
          # If user_content_edit is for a GistComment perform extra validation.
          # `prefix` value is user supplied and can not be trusted to match model type
          # https://github.com/github/repos/issues/11529
          next edit_object unless edit_object&.user_content_type == "GistComment"

          Platform::Loaders::ActiveRecord.load(::Gist, parsed_id.parts[:gist_id]).then do |gist|
            next nil unless gist && edit_object

            edit_object.async_user_content.then do |comment|
              # Only return the user_content_edit if the comment and the global_id have the same gist ID
              next edit_object if comment&.gist_id == gist.id

              nil
            end
          end
        end
      end

      # This method special cases edits on gist comments in order to protect
      # secret gists. Gists aren't backed by abilities, and the only thing
      # protecting them is the secret-ness of the gist's "repo name". We don't
      # a user to be able to load the edit history of a secret gist comment
      # just because they have the UserContentEdit's id.
      def self.load_from_global_id(id)
        if id.include?(":")
          gist_repo_name_or_type, content_edit_id = id.split(":", 2)

          if ::UserContentEditable.is_custom_edit_class?(gist_repo_name_or_type)
            Loaders::ActiveRecord.load("::#{gist_repo_name_or_type}".constantize, content_edit_id.to_i)
          else
            Promise.all([
              Loaders::ActiveRecord.load(::Gist, gist_repo_name_or_type, column: :repo_name),
              Loaders::ActiveRecord.load(::UserContentEdit, content_edit_id.to_i),
            ]).then do |gist, edit|
              next nil unless edit
              next nil unless gist
              edit.async_user_content.then do |comment|
                # make sure the gist the comment is on is the same as the gist
                # in the global relay id
                if comment && comment.gist_id == gist.id
                  edit
                else
                  nil
                end
              end
            end
          end
        else
          async_edit = Promise.all([
            Platform::Loaders::ActiveRecord.load(::CommitCommentEdit, id.to_i, column: :user_content_edit_id),
            Platform::Loaders::ActiveRecord.load(::IssueEdit, id.to_i, column: :user_content_edit_id),
            Platform::Loaders::ActiveRecord.load(::IssueCommentEdit, id.to_i, column: :user_content_edit_id),
            Platform::Loaders::ActiveRecord.load(::PullRequestReviewEdit, id.to_i, column: :user_content_edit_id),
            Platform::Loaders::ActiveRecord.load(::PullRequestReviewCommentEdit, id.to_i, column: :user_content_edit_id),
            Platform::Loaders::ActiveRecord.load(::RepositoryAdvisoryEdit, id.to_i, column: :user_content_edit_id),
            Platform::Loaders::ActiveRecord.load(::RepositoryAdvisoryCommentEdit, id.to_i, column: :user_content_edit_id),
          ]).then do |results|
            results.compact.first || Platform::Loaders::ActiveRecord.load(::UserContentEdit, id.to_i)
          end

          async_edit.then do |edit|
            next nil unless edit

            edit.async_user_content.then do |content|
              # don't leak existence of secret gists - they aren't enumerable
              # by UserContentEdit id
              if content.is_a? ::GistComment
                nil
              else
                edit
              end
            end
          end
        end
      end
    end
  end
end
