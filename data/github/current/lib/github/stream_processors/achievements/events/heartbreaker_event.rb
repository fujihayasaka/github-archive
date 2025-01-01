# typed: false
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Achievements
      module Events
        class HeartbreakerEvent < AchievementEvent
          ACHIEVABLE_CLASS = Achievable::Heartbreaker
          MATCHING_SCHEMA = [/github\.v1\.IssueClose\Z/].freeze
          UNDER_THRESHOLD_SKIP_MESSAGE =
            "User did not have enough reactions to cross the heartbreaker threshold."
          UNLOCKING_MODEL_NOT_FOUND_SKIP_MESSAGE = "Unlocking model cannot be found."
          USER_NOT_AUTHOR_SKIP_MESSAGE = "User was not the author of the unlocking model."
          USER_NOT_FOUND_SKIP_MESSAGE = "User cannot be found."
          USER_ALREADY_ACHIEVED_SKIP_MESSAGE = "User already has the heartbreaker achievement."
          CLOSED_AS_SOMETHING_OTHER_THAN_NOT_PLANNED_SKIP_MESSAGE =
            "Issue was closed as something other than not planned."

          private_achievement eligible_if: true
          public_achievement eligible_if: :repository_public?
          achieving_user :user
          achievement_visibility :repository_visibility
          wait_for_replication [Reaction.cluster_name, IssueReaction.cluster_name]

          def skip_reason
            return @_skip_reason if defined?(@_skip_reason)

            @_skip_reason = super || begin
              if !unlocking_model
                UNLOCKING_MODEL_NOT_FOUND_SKIP_MESSAGE
              elsif user_not_unlocking_model_author?
                USER_NOT_AUTHOR_SKIP_MESSAGE
              elsif !user
                USER_NOT_FOUND_SKIP_MESSAGE
              elsif already_has_highest_tier_achievement?
                USER_ALREADY_ACHIEVED_SKIP_MESSAGE
              elsif under_threshold?
                UNDER_THRESHOLD_SKIP_MESSAGE
              elsif !closed_as_not_planned?
                CLOSED_AS_SOMETHING_OTHER_THAN_NOT_PLANNED_SKIP_MESSAGE
              end
            end
          end

          def unlocking_model
            return @_unlocking_model if defined?(@_unlocking_model)

            @_unlocking_model = with_read { Issue.find_by(id: unlocking_issue_id) } # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          end

          private

          def under_threshold?
            reactions_count < next_achievement_tier_threshold
          end

          def closed_as_not_planned?
            message.value.dig(:issue, :issue_state_reason) == :NOT_PLANNED
          end

          def user_not_unlocking_model_author?
            unlocking_model&.user_id != actor_id
          end

          def unlocking_issue_id
            return @_unlocking_issue_id if defined?(@_unlocking_issue_id)

            @_unlocking_issue_id = message.value.dig(:issue, :id)
          end

          def reactions_count
            unlocking_model.reactions.limit(next_achievement_tier_threshold + 1).size
          end
        end
      end
    end
  end
end
