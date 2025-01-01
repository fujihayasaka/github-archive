# typed: false
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Achievements
      module Events
        class PullSharkEvent < AchievementEvent
          ACHIEVABLE_CLASS = Achievable::PullShark
          MATCHING_SCHEMA = [/github\.v1\.PullRequestMerge\Z/].freeze
          UNDER_THRESHOLD_SKIP_MESSAGE = "User has not reached the threshold to unlock or advance the achievement."
          UNLOCKING_MODEL_NOT_FOUND_SKIP_MESSAGE = "Unlocking model cannot be found."
          USER_NOT_FOUND_SKIP_MESSAGE = "User cannot be found."
          USER_ALREADY_ACHIEVED_HIGHEST_TIER_SKIP_MESSAGE = "User already has the highest tier pull shark achievement."

          SLICE_SIZE = 100

          private_achievement eligible_unless: :private_and_public_pull_request_count_under_threshold?
          public_achievement eligible_unless: :public_only_pull_request_count_under_threshold?
          achieving_user :user
          achievement_visibility :repository_visibility
          wait_for_replication PullRequest.cluster_name

          def skip_reason
            return @_skip_reason if defined?(@_skip_reason)

            @_skip_reason = super || begin
              if !unlocking_model
                UNLOCKING_MODEL_NOT_FOUND_SKIP_MESSAGE
              elsif !user
                USER_NOT_FOUND_SKIP_MESSAGE
              elsif already_has_both_highest_tier_achievements?
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
            public_only_pull_request_count_under_threshold? &&
              private_and_public_pull_request_count_under_threshold?
          end

          def private_and_public_pull_request_count_under_threshold?
            pull_request_counts[:private_and_public_count] <
              next_achievement_tier_threshold(subject_visibility: :PRIVATE)
          end

          def public_only_pull_request_count_under_threshold?
            pull_request_counts[:public_only_count] <
              next_achievement_tier_threshold(subject_visibility: :PUBLIC)
          end

          def pull_request_counts
            return @_pull_request_counts if defined?(@_pull_request_counts)

            @_pull_request_counts = with_read do
              repository_ids = user.pull_requests.distinct.pluck(:repository_id)

              results = { private_and_public_count: 0, public_only_count: 0 }

              repository_ids.each_slice(SLICE_SIZE) do |repo_ids_slice|
                public_repository_ids = Repository.where(id: repo_ids_slice).public_scope.pluck(:id)

                results[:private_and_public_count] += user.pull_requests.
                  where(repository_id: repo_ids_slice, user_hidden: false).
                  where.not(merged_at: nil).
                  limit(next_achievement_tier_threshold(subject_visibility: :PRIVATE) + 1).
                  size
                results[:public_only_count] += user.pull_requests.
                  where(repository_id: public_repository_ids, user_hidden: false).
                  where.not(merged_at: nil).
                  limit(next_achievement_tier_threshold(subject_visibility: :PUBLIC) + 1).
                  size
              end

              results
            end
          end
        end
      end
    end
  end
end
