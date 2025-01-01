# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Reaction < Platform::Objects::Base
      description "An emoji reaction to a particular piece of content."

      PREFIX_TO_REACTION_TYPE = {
        rccr: ::CommitCommentReaction,
        rir: ::IssueReaction,
        ricr: ::IssueCommentReaction,
        rprr: ::PullRequestReviewReaction,
        rprrcr: ::PullRequestReviewCommentReaction,
      }

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, reaction)
        reaction.async_subject.then do |reaction_subject|
          permission.rewrite_reaction_subject(reaction_subject).then do |subject_type, subject|
            permission.typed_can_access?(subject_type, subject)
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_user.then do |user|
          if user && user.hide_from_user?(permission.viewer)
            false
          else
            object.async_subject.then do |subject|
              permission.rewrite_reaction_subject(subject).then do |subject_type, subject|
                permission.typed_can_see?(subject_type, subject)
              end
            end
          end
        end
      end

      def self.load_from_next_global_id(parsed_id)
        if parsed_id.parts.keys.include?(:discussion_id)
          Platform::Objects.async_find_record_by_id(DiscussionReaction, parsed_id.id)
        elsif parsed_id.parts.keys.include?(:discussion_comment_id)
          Platform::Objects.async_find_record_by_id(DiscussionCommentReaction, parsed_id.id)
        elsif parsed_id.type == "Reaction" && PREFIX_TO_REACTION_TYPE.key?(parsed_id.parts[:prefix])
          type = PREFIX_TO_REACTION_TYPE[parsed_id.parts[:prefix]]
          Platform::Objects.async_find_record_by_id(type, parsed_id.id)
        else
          super
        end
      end

      scopeless_tokens_as_minimum

      implements_node templates: [
        [:rccr, :repo_id, :commit_comment_id, :reaction_id],
        [:rir, :repo_id, :issue_id, :reaction_id],
        [:ricr, :repo_id, :issue_comment_id, :reaction_id],
        [:rprr, :repo_id, :pull_request_review_id, :reaction_id],
        [:rprrcr, :repo_id, :pull_request_review_comment_id, :reaction_id],
        [:rdr, :repo_id, :discussion_id, :reaction_id],
        [:rdcr, :repo_id, :discussion_comment_id, :reaction_id],
        [:rrr, :repo_id, :release_id, :reaction_id],
        [:rrar, :repo_id, :repository_advisory_id, :reaction_id],
        [:rracr, :repo_id, :repository_advisory_comment_id, :reaction_id],
        [:ottdr, :org_id, :team_id, :team_discussion_id, :reaction_id],
        [:ottdcr, :org_id, :team_id, :team_discussion_comment_id, :reaction_id]
      ], as: "REA", ready_date: Platform::Helpers::GlobalId::COHORT_3 do |reaction|
        reaction.async_subject.then do |subject|
          subject_key = subject_globalid_key(subject)

          raise(Errors::NotImplemented, "reaction subject '#{subject}' does not have a global id template") unless subject_key

          prefix = subject_to_globalid_prefix(subject)

          raise(Errors::NotImplemented, "reaction subject '#{subject}' does not have a global id prefix") unless prefix

          if subject_globalid_requires_repository(subject)
            subject.async_repository.then do |repo|
              {
                :prefix => prefix,
                :repo_id => repo.id,
                subject_key.to_sym => subject.id,
                :reaction_id => reaction.id
              }
            end
          elsif subject_globalid_requires_team(subject)
            subject.async_team.then do |team|
              {
                :prefix => prefix,
                :org_id => team&.organization_id,
                :team_id => team&.id,
                subject_key.to_sym => subject.id,
                :reaction_id => reaction.id
              }
            end
          else
            raise Errors::NotImplemented, "reaction subject '#{subject}' is unknown"
          end
        end
      end

      field :content, Enums::ReactionContent, "Identifies the emoji reaction.", null: false

      created_at_field

      database_id_field

      field :reactable, Interfaces::Reactable, description: "The reactable piece of content", null: false

      def reactable
        @object.async_subject.then do |subject|
          if subject.try(:pull_request_id).present?
            subject.async_pull_request
          else
            subject
          end
        end
      end

      field :user, User, method: :async_user, description: "Identifies the user who created this reaction.", null: true

      def self.subject_globalid_key(subject)
        case subject
        when ::CommitComment
          :commit_comment_id
        when ::Discussion
          :discussion_id
        when ::DiscussionComment
          :discussion_comment_id
        when ::DiscussionPost
          :team_discussion_id
        when ::DiscussionPostReply
          :team_discussion_comment_id
        when ::Issue
          :issue_id
        when ::IssueComment
          :issue_comment_id
        when ::PullRequestReview
          :pull_request_review_id
        when ::PullRequestReviewComment
          :pull_request_review_comment_id
        when ::Release
          :release_id
        when ::RepositoryAdvisory
          :repository_advisory_id
        when ::RepositoryAdvisoryComment
          :repository_advisory_comment_id
        else
          nil
        end
      end
      private_class_method :subject_globalid_key

      def self.subject_globalid_requires_repository(subject)
        case subject
        when ::CommitComment, ::Discussion, ::DiscussionComment, ::Issue, ::IssueComment, ::PullRequestReview, ::PullRequestReviewComment, ::Release, ::RepositoryAdvisory, ::RepositoryAdvisoryComment
          true
        else
          false
        end
      end
      private_class_method :subject_globalid_requires_repository

      def self.subject_globalid_requires_team(subject)
        case subject
        when ::DiscussionPost, ::DiscussionPostReply
          true
        else
          false
        end
      end
      private_class_method :subject_globalid_requires_team

      def self.subject_to_globalid_prefix(subject)
        case subject
        when ::CommitComment
          :rccr
        when ::Discussion
          :rdr
        when ::DiscussionComment
          :rdcr
        when ::DiscussionPost
          :ottdr
        when ::DiscussionPostReply
          :ottdcr
        when ::Issue
          :rir
        when ::IssueComment
          :ricr
        when ::PullRequestReview
          :rprr
        when ::PullRequestReviewComment
          :rprrcr
        when ::Release
          :rrr
        when ::RepositoryAdvisory
          :rrar
        when ::RepositoryAdvisoryComment
          :rracr
        else
          nil
        end
      end
      private_class_method :subject_to_globalid_prefix

    end
  end
end
