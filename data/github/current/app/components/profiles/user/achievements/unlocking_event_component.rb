# typed: true
# frozen_string_literal: true

module Profiles
  module User
    module Achievements
      class UnlockingEventComponent < ApplicationComponent
        # Map unlocking_model_type values to the components responsible for rendering a stylized link to unlocking
        # models of that type.
        #
        # Done with a Hash instead of .contantize shenanigans so the component classes are recognized as "used."
        UNLOCKING_MODEL_COMPONENTS = {
          "AchievementRepositoryList" => Profiles::User::Achievements::UnlockingEvents::AchievementRepositoryListComponent,
          "Commit" => Profiles::User::Achievements::UnlockingEvents::CommitComponent,
          "CommitComment" => Profiles::User::Achievements::UnlockingEvents::CommitCommentComponent,
          "Discussion" => Profiles::User::Achievements::UnlockingEvents::DiscussionComponent,
          "DiscussionComment" => Profiles::User::Achievements::UnlockingEvents::DiscussionCommentComponent,
          "DiscussionPost" => Profiles::User::Achievements::UnlockingEvents::DiscussionPostComponent,
          "DiscussionPostReply" => Profiles::User::Achievements::UnlockingEvents::DiscussionPostReplyComponent,
          "Issue" => Profiles::User::Achievements::UnlockingEvents::IssueComponent,
          "IssueComment" => Profiles::User::Achievements::UnlockingEvents::IssueCommentComponent,
          "PullRequest" => Profiles::User::Achievements::UnlockingEvents::PullRequestComponent,
          "PullRequestReview" => Profiles::User::Achievements::UnlockingEvents::PullRequestReviewComponent,
          "PullRequestReviewComment" => Profiles::User::Achievements::UnlockingEvents::PullRequestReviewCommentComponent,
          "Release" => Profiles::User::Achievements::UnlockingEvents::ReleaseComponent,
          "Repository" => Profiles::User::Achievements::UnlockingEvents::RepositoryComponent,
          "RepositoryAdvisory" => Profiles::User::Achievements::UnlockingEvents::RepositoryAdvisoryComponent,
          "RepositoryAdvisoryComment" => Profiles::User::Achievements::UnlockingEvents::RepositoryAdvisoryCommentComponent,
          "Sponsorship" => Profiles::User::Achievements::UnlockingEvents::SponsorshipComponent,
        }.freeze

        # achievement - Achievement model describing this unlocked tier.
        # visible_models - Set containing the subset of unlocking models associated with achievements that are
        #   permitted to be seen by authzd and CAP filters on the current request.
        # is_hovercard - Boolean indicating whether this is being rendered in a hovercard.
        # profile_user - User model of the profile being viewed.
        def initialize(achievement:, visible_models:, is_hovercard: false, profile_user: nil)
          @achievement = achievement
          @visible_models = visible_models
          @is_hovercard = is_hovercard
          @profile_user = profile_user
        end

        def call
          unlocking_model_type = achievement.unlocking_model_type

          if unlocking_model_type == "Repository" && achievement.achievable.needs_unlocking_oid?
            unlocking_model_type = "Commit"
          end

          component_class = UNLOCKING_MODEL_COMPONENTS.fetch(
            unlocking_model_type,
            Profiles::User::Achievements::UnlockingEvents::UnknownComponent,
          )
          component = component_class.new(
            achievement: achievement,
            visible_models: visible_models,
            is_hovercard: is_hovercard,
            profile_user: profile_user,
          )

          render(component)
        end

        private

        attr_reader :achievement, :visible_models, :is_hovercard, :profile_user

        def render?
          achievement.present?
        end
      end
    end
  end
end
