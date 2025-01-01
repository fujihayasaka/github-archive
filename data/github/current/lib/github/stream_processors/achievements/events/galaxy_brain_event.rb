# typed: false
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Achievements
      module Events
        class GalaxyBrainEvent < AchievementEvent
          ACHIEVABLE_CLASS = Achievable::GalaxyBrain
          MATCHING_SCHEMA = [/github\.discussions\.v1\.DiscussionCommentMarkAsAnswer\Z/].freeze
          UNDER_THRESHOLD_SKIP_MESSAGE = "User has not reached the threshold to unlock or advance the achievement."
          UNLOCKING_MODEL_NOT_FOUND_SKIP_MESSAGE = "Unlocking model cannot be found."
          ACTOR_OR_AUTHOR_NOT_FOUND_SKIP_MESSAGE = "Comment author or actor marking comment as answer cannot be found."
          USER_ALREADY_ACHIEVED_HIGHEST_TIER_SKIP_MESSAGE = "User already has the highest tier galaxy brain achievement."
          AUTHOR_SAME_AS_ACTOR_SKIP_MESSAGE = "Comment author is the same as the actor marking it as the answer."

          BATCH_SIZE = 100

          private_achievement eligible_unless: :private_and_public_count_under_threshold?
          public_achievement eligible_unless: :public_only_count_under_threshold?
          achieving_user :user
          achievement_visibility :repository_visibility
          wait_for_replication [DiscussionEvent.cluster_name, DiscussionComment.cluster_name]

          def skip_reason
            return @_skip_reason if defined?(@_skip_reason)

            @_skip_reason = super || begin
              if !unlocking_model
                UNLOCKING_MODEL_NOT_FOUND_SKIP_MESSAGE
              elsif author_same_as_actor?
                AUTHOR_SAME_AS_ACTOR_SKIP_MESSAGE
              elsif !actor || !user
                ACTOR_OR_AUTHOR_NOT_FOUND_SKIP_MESSAGE
              elsif already_has_both_highest_tier_achievements?
                USER_ALREADY_ACHIEVED_HIGHEST_TIER_SKIP_MESSAGE
              elsif under_threshold?
                UNDER_THRESHOLD_SKIP_MESSAGE
              end
            end
          end

          def unlocking_model
            return @_unlocking_model if defined?(@_unlocking_model)

            discussion_comment_id = message.value.dig(:discussion_comment, :id)
            @_unlocking_model = with_read { DiscussionComment.find_by(id: discussion_comment_id) }
          end

          def user_message_path
            [:author]
          end

          private

          def author_same_as_actor?
            author_id == actor_id
          end

          def author_id
            message.value.dig(:author, :id)
          end

          def under_threshold?
            public_only_count_under_threshold? && private_and_public_count_under_threshold?
          end

          def private_and_public_count_under_threshold?
            answered_discussions_count[:private_and_public_count] <
              next_achievement_tier_threshold(subject_visibility: :PRIVATE)
          end

          def public_only_count_under_threshold?
            answered_discussions_count[:public_only_count] <
              next_achievement_tier_threshold(subject_visibility: :PUBLIC)
          end

          def answered_discussions_count
            return @_answered_discussions_count if defined?(@_answered_discussions_count)

            @_answered_discussions_count = with_read do
              all_repository_ids = user.discussion_comments.pluck(:repository_id).to_set

              all_repository_visibility_and_ids = Repository.
                where(id: all_repository_ids).
                pluck(:public, :owner_id, :id)

              all_repository_visibility_and_ids = all_repository_visibility_and_ids.reject do |_, owner_id, _|
                owner_id.in?(ORGANIZATION_IDS_BLOCKED_FROM_ACHIEVEMENT_TRACKING)
              end

              public_repository_ids = Set.new(
                Array(all_repository_visibility_and_ids.group_by(&:first)[true]).transpose.last,
              )

              all_repository_ids = Set.new(all_repository_visibility_and_ids.transpose.last)

              private_and_public_comment_ids = Set.new
              public_only_comment_ids = Set.new
              last_id = -1

              max_private_and_public = next_achievement_tier_threshold(subject_visibility: :PRIVATE)
              max_public_only = next_achievement_tier_threshold(subject_visibility: :PUBLIC)

              loop do
                answer_ids_and_repository_ids = user.
                  discussion_comments.
                  where(repository_id: all_repository_ids).
                  where(id: last_id..).
                  chosen_answers.
                  limit(BATCH_SIZE).
                  order(:id).
                  pluck(:id, :repository_id)

                last_id = answer_ids_and_repository_ids.last&.first

                all_answer_ids, repository_ids = answer_ids_and_repository_ids.transpose
                public_answer_ids, _ = answer_ids_and_repository_ids.
                  select { |_, repository_id| public_repository_ids.include?(repository_id) }.
                  transpose

                private_and_public_comment_ids.merge(
                  DiscussionEvent.
                    where(comment_id: all_answer_ids).
                    answer_marked.
                    where.not(actor_id: user.id).
                    distinct.
                    pluck(:comment_id)
                )

                public_only_comment_ids.merge(
                  DiscussionEvent.
                    where(comment_id: public_answer_ids).
                    answer_marked.
                    where.not(actor_id: user.id).
                    distinct.
                    pluck(:comment_id)
                )

                if answer_ids_and_repository_ids.size < BATCH_SIZE ||
                    private_and_public_comment_ids.size >= max_private_and_public ||
                    public_only_comment_ids.size >= max_public_only
                  break
                end
              end

              {
                private_and_public_count: private_and_public_comment_ids.size,
                public_only_count: public_only_comment_ids.size,
              }
            end
          end
        end
      end
    end
  end
end
