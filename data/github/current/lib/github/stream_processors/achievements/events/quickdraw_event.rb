# typed: false
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Achievements
      module Events
        class QuickdrawEvent < AchievementEvent
          ACHIEVABLE_CLASS = Achievable::Quickdraw
          MATCHING_SCHEMA = [
            /github\.v1\.IssueClose\Z/,
            /github\.v1\.PullRequestClose\Z/,
          ].freeze
          UNDER_THRESHOLD_SKIP_MESSAGE =
            "User did not close this issue/pull request within the threshold amount of time."
          UNLOCKING_MODEL_NOT_FOUND_SKIP_MESSAGE = "Unlocking model cannot be found."
          USER_NOT_AUTHOR_SKIP_MESSAGE = "User was not the author of the unlocking model."
          USER_NOT_FOUND_SKIP_MESSAGE = "User cannot be found."
          USER_ALREADY_ACHIEVED_SKIP_MESSAGE = "User already has the quickdraw achievement."

          private_achievement eligible_if: true
          public_achievement eligible_if: :repository_public?
          achieving_user :user
          achievement_visibility :repository_visibility
          wait_for_replication [PullRequest.cluster_name, Issue.cluster_name]

          def skip_reason
            return @_skip_reason if defined?(@_skip_reason)

            @_skip_reason = super || begin
              if !unlocking_model
                UNLOCKING_MODEL_NOT_FOUND_SKIP_MESSAGE
              elsif user_not_unlocking_model_author?
                USER_NOT_AUTHOR_SKIP_MESSAGE
              elsif !user
                USER_NOT_FOUND_SKIP_MESSAGE
              elsif already_has_both_highest_tier_achievements?
                USER_ALREADY_ACHIEVED_SKIP_MESSAGE
              elsif !under_threshold?
                UNDER_THRESHOLD_SKIP_MESSAGE
              end
            end
          end

          def unlocking_model
            return @_unlocking_model if defined?(@_unlocking_model)

            @_unlocking_model = if for_pull_request?
              with_read { PullRequest.find_by(id: unlocking_pull_request_id) }
            elsif for_issue?
              with_read { Issue.find_by(id: unlocking_issue_id) }
            end
          end

          private

          def under_threshold?
            closing_time = unlocking_model.closed_at || Time.at(message.timestamp)
            (closing_time - unlocking_model.created_at) <= next_achievement_tier_threshold
          end

          def user_not_unlocking_model_author?
            unlocking_model&.user_id != actor_id
          end

          def unlocking_issue_id
            return @_unlocking_issue_id if defined?(@_unlocking_issue_id)

            @_unlocking_issue_id = message.value.dig(:issue, :id)
          end

          def unlocking_pull_request_id
            return @_unlocking_pull_request_id if defined?(@_unlocking_pull_request_id)

            @_unlocking_pull_request_id = message.value.dig(:pull_request, :id)
          end

          def for_issue?
            !!unlocking_issue_id
          end

          def for_pull_request?
            !!unlocking_pull_request_id
          end
        end
      end
    end
  end
end
