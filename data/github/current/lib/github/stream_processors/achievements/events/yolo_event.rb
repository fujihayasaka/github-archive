# typed: false
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Achievements
      module Events
        class YoloEvent < AchievementEvent
          ACHIEVABLE_CLASS = Achievable::Yolo
          MATCHING_SCHEMA = [/github\.v1\.PullRequestMerge\Z/].freeze
          UNDER_THRESHOLD_SKIP_MESSAGE =
            "User did not merge this pull request under the required criteria."
          UNLOCKING_MODEL_NOT_FOUND_SKIP_MESSAGE = "Unlocking model cannot be found."
          USER_NOT_AUTHOR_SKIP_MESSAGE = "User was not the author of the unlocking model."
          USER_NOT_FOUND_SKIP_MESSAGE = "User cannot be found."
          USER_ALREADY_ACHIEVED_SKIP_MESSAGE = "User already has the yolo achievement."
          TIME_THRESHOLD = 5.minutes.freeze
          QUALIFYING_STATUSES = %w(pending queued expected).freeze

          private_achievement eligible_if: true
          public_achievement eligible_if: :repository_public?
          achieving_user :user
          achievement_visibility :repository_visibility
          wait_for_replication PullRequestReview.cluster_name

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
              elsif !qualifying?
                UNDER_THRESHOLD_SKIP_MESSAGE
              end
            end
          end

          def unlocking_model
            return @_unlocking_model if defined?(@_unlocking_model)

            @_unlocking_model = if pull_request_id = message.value.dig(:pull_request, :id)
              with_read { PullRequest.find_by(id: pull_request_id) }
            end
          end

          private

          def qualifying?
            all_review_requests_are_pending? ||
              all_reviews_are_requesting_changes? ||
              checks_still_pending_or_queued_and_under_time_threshold?
          end

          def user_not_unlocking_model_author?
            unlocking_model&.user_id != actor_id
          end

          def all_review_requests_are_pending?
            with_read do
              if reviews.none?
                scope = unlocking_model.review_requests

                total_review_requests = scope.size
                total_review_requests > 0 && scope.pending.size == total_review_requests
              end
            end
          end

          def all_reviews_are_requesting_changes?
            with_read do
              if reviews.any?
                review_counts_by_state = reviews.group(:state).count
                review_counts_by_state[reviews.state_value(:changes_requested)] ==
                  review_counts_by_state.values.sum
              end
            end
          end

          def checks_still_pending_or_queued_and_under_time_threshold?
            with_read do
              check_suites = if unlocking_model.changed_commits.any?
                unlocking_model.matching_check_suites
              else
                []
              end

              has_check_suites = check_suites.any?
              statuses = unlocking_model.repository.statuses.where(sha: unlocking_model.head_sha)
              has_statuses = statuses.any?

              if has_check_suites || has_statuses
                checks = [merged_before_time_threshold_elapsed?]
                checks << all_checks_are_queued_or_pending?(check_suites) if has_check_suites
                checks << all_statuses_are_expected_or_pending?(statuses) if has_statuses

                checks.all?
              end
            end
          end

          def all_checks_are_queued_or_pending?(check_suites)
            check_suite_counts_by_status = check_suites.group(:status).count
            check_suite_counts_by_status.values.sum ==
              check_suite_counts_by_status.values_at(*QUALIFYING_STATUSES).compact.sum
          end

          def all_statuses_are_expected_or_pending?(statuses)
            status_counts_by_state = statuses.group(:state).count
            status_counts_by_state.values.sum ==
              status_counts_by_state.values_at(*QUALIFYING_STATUSES).compact.sum
          end

          def merged_before_time_threshold_elapsed?
            merged_time = unlocking_model.merged_at || Time.at(message.timestamp)
            (merged_time - unlocking_model.created_at) <= TIME_THRESHOLD
          end

          def reviews
            @_reviews ||= with_read { unlocking_model.reviews }
          end
        end
      end
    end
  end
end
