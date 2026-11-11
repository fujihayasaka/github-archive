# typed: false
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Achievements
      module Events
        class PairExtraordinaireEvent < AchievementEvent
          ACHIEVABLE_CLASS = Achievable::PairExtraordinaire
          MATCHING_SCHEMA = [/github\.v1\.PullRequestMerge\Z/].freeze
          NO_CO_AUTHORS_SKIP_MESSAGE = "No commits had co authors."
          UNLOCKING_MODEL_NOT_FOUND_SKIP_MESSAGE = "Unlocking model cannot be found."
          ALL_USERS_ALREADY_ACHIEVED_SKIP_MESSAGE =
            "All authors already have the highest Pair Extraordinaire achievement."

          private_achievement eligible_if: :private_count_above_threshold?, send_args: true
          public_achievement eligible_if: :public_count_above_threshold?, send_args: true
          achieving_users :authors
          achievement_visibility :repository_visibility

          def skip_reason
            return @_skip_reason if defined?(@_skip_reason)

            @_skip_reason = super || begin
              if !unlocking_model
                UNLOCKING_MODEL_NOT_FOUND_SKIP_MESSAGE
              elsif achieving_users.size < 2
                NO_CO_AUTHORS_SKIP_MESSAGE
              elsif all_achieving_users_already_have_both_highest_tier_achievements?
                ALL_USERS_ALREADY_ACHIEVED_SKIP_MESSAGE
              end
            end
          end

          def unlocking_model
            return @_unlocking_model if defined?(@_unlocking_model)

            @_unlocking_model = if pull_request_id = message.value.dig(:pull_request, :id)
              with_read { PullRequest.find_by(id: pull_request_id) }
            end
          end

          def authors
            return @_authors if defined?(@_authors)

            @_authors = with_read do
              pairing_authors = unlocking_model.changed_commits.flat_map do |commit|
                next unless commit.author_emails.size > 1

                gh_users = Promise.all(commit.author_actors.map(&:async_user)).sync.compact
                next unless gh_users.size > 1

                gh_users
              end

              pairing_authors.compact.uniq
            end
          end

          def user_message_path
            [:author]
          end

          private

          def all_achieving_users_already_have_both_highest_tier_achievements?
            achieving_users.all? do |user|
              already_has_both_highest_tier_achievements?(subject_user: user)
            end
          end

          def private_count_above_threshold?(subject_user, private_count)
            next_threshold = next_achievement_tier_threshold(
              subject_user: subject_user,
              subject_visibility: :PRIVATE,
            )

            private_count >= next_threshold
          end

          def public_count_above_threshold?(subject_user, public_count)
            next_threshold = next_achievement_tier_threshold(
              subject_user: subject_user,
              subject_visibility: :PUBLIC,
            )

            public_count >= next_threshold
          end
        end
      end
    end
  end
end
