# typed: false
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Achievements
      module Events
        class OpenSourcererEvent < AchievementEvent
          ACHIEVABLE_CLASS = Achievable::OpenSourcerer
          MATCHING_SCHEMA = [/github\.v1\.PullRequestMerge\Z/].freeze
          UNDER_THRESHOLD_SKIP_MESSAGE = "User has not reached the threshold to unlock or advance the achievement."
          UNLOCKING_MODEL_NOT_FOUND_SKIP_MESSAGE = "Unlocking model cannot be found."
          USER_NOT_FOUND_SKIP_MESSAGE = "User cannot be found."
          USER_ALREADY_ACHIEVED_HIGHEST_TIER_SKIP_MESSAGE = "User already has the highest tier open sourcerer achievement."
          PRIVATE_REPO_SKIP_MESSAGE = "Pull request is not from a public repository."
          SLICE_SIZE = 100

          private_achievement eligible_if: true
          public_achievement eligible_if: :repository_public?
          achieving_user :user
          achievement_visibility :repository_visibility
          wait_for_replication PullRequest.cluster_name

          def skip_reason
            return @_skip_reason if defined?(@_skip_reason)

            @_skip_reason = super || begin
              if private_repository?
                PRIVATE_REPO_SKIP_MESSAGE
              elsif !unlocking_model
                UNLOCKING_MODEL_NOT_FOUND_SKIP_MESSAGE
              elsif !user
                USER_NOT_FOUND_SKIP_MESSAGE
              elsif already_has_highest_tier_achievement?
                USER_ALREADY_ACHIEVED_HIGHEST_TIER_SKIP_MESSAGE
              elsif under_threshold?
                UNDER_THRESHOLD_SKIP_MESSAGE
              end
            end
          end

          def unlocking_model
            return @_unlocking_model if defined?(@_unlocking_model)

            pull_request_id = message.value.dig(:pull_request, :id)
            @_unlocking_model = with_read { PullRequest.find_by(id: pull_request_id) }
          end

          def user_message_path
            [:author]
          end

          private

          def under_threshold?
            oss_repo_count < next_threshold
          end

          def private_repository?
            visibility == :PRIVATE
          end

          def oss_repo_count
            with_read do
              repo_ids = user.pull_requests.distinct.pluck(:repository_id)

              repo_ids.each_slice(SLICE_SIZE).inject(0) do |total, repo_ids_slice|
                remaining = next_threshold - total
                break total if remaining <= 0

                public_repo_ids = Repository.where(id: repo_ids_slice).public_scope.pluck(:id)

                total + user.
                  pull_requests.
                  where.not(merged_at: nil).
                  where(repository_id: public_repo_ids, user_hidden: false).
                  distinct.
                  limit(remaining + 1).
                  pluck(:repository_id).
                  size
              end
            end
          end

          def next_threshold
            @_next_threshold ||= next_achievement_tier_threshold
          end
        end
      end
    end
  end
end
