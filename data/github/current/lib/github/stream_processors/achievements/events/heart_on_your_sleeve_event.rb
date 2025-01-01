# typed: false
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Achievements
      module Events
        class HeartOnYourSleeveEvent < AchievementEvent
          ACHIEVABLE_CLASS = Achievable::HeartOnYourSleeve
          MATCHING_SCHEMA = [
            /github\.v1\.ReactionCreate\Z/,
            /github\.discussions\.v1\.DiscussionReactionCreate\Z/,
            /github\.discussions\.v1\.DiscussionCommentReactionCreate\Z/,
          ].freeze
          UNDER_THRESHOLD_SKIP_MESSAGE = "User has not reached the threshold to unlock or advance the achievement."
          UNLOCKING_MODEL_NOT_FOUND_SKIP_MESSAGE = "Unlocking model cannot be found."
          USER_NOT_FOUND_SKIP_MESSAGE = "User cannot be found."
          USER_ALREADY_ACHIEVED_HIGHEST_TIER_SKIP_MESSAGE = "User already has the highest tier heart on your sleeve achievement."
          EXTRACTED_REACTION_SUBJECT_TYPES = ::Reactable::SUBJECT_TYPES_WITH_SEPARATE_REACTION_MODELS.to_a.concat(%w[Discussion DiscussionComment]).freeze
          LEGACY_REACTION_SUBJECT_TYPES = (Reaction::VALID_SUBJECT_TYPES - EXTRACTED_REACTION_SUBJECT_TYPES).freeze
          REACTION_SUBJECTS_WITHOUT_REPO = %w[DiscussionPost DiscussionPostReply].freeze

          private_achievement eligible_unless: :private_and_public_count_under_threshold?
          public_achievement eligible_unless: :public_only_count_under_threshold?
          achieving_user :user
          achievement_visibility :repository_visibility
          wait_for_replication(
            EXTRACTED_REACTION_SUBJECT_TYPES.map { |t| "#{t}Reaction".constantize.cluster_name } +
            [Reaction.cluster_name]
          )

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

          def user_or_org_opted_out?
            if (subject_type = message.value.dig(:subject_type)).in?(REACTION_SUBJECTS_WITHOUT_REPO)
              subject = subject_type.constantize.find_by(id: message.value.dig(:subject_id))

              if subject
                subject.organization.profile_settings.
                  all_private_projects_opted_out_of_achievements_tracking?
              end
            else
              super
            end
          end

          def unlocking_model
            return @_unlocking_model if defined?(@_unlocking_model)

            @_unlocking_model = discussion_comment || discussion || reaction_subject
          end

          private

          def under_threshold?
            public_only_count_under_threshold? && private_and_public_count_under_threshold?
          end

          def private_and_public_count_under_threshold?
            reaction_count[:private_and_public_count] <
              next_achievement_tier_threshold(subject_visibility: :PRIVATE)
          end

          def public_only_count_under_threshold?
            reaction_count[:public_only_count] <
              next_achievement_tier_threshold(subject_visibility: :PUBLIC)
          end

          def discussion_comment
            return @_discussion_comment if defined?(@_discussion_comment)

            @_discussion_comment = begin
              if discussion_comment_id = message.value.dig(:discussion_comment, :id)
                with_read { DiscussionComment.find_by(id: discussion_comment_id) }
              end
            end
          end

          def discussion
            return @_discussion if defined?(@_discussion)

            @_discussion = begin
              if discussion_id = message.value.dig(:discussion, :id)
                with_read { Discussion.find_by(id: discussion_id) }
              end
            end
          end

          def reaction_subject
            return @_reaction_subject if defined?(@_reaction_subject)

            @_reaction_subject = begin
              if (reaction_subject_id = message.value.dig(:subject_id)) && (subject_type = message.value.dig(:subject_type))
                subject_type_class = subject_type.constantize
                with_read { subject_type_class.find_by(id: reaction_subject_id) } # domain-isolation-query-violation:ignore:packages/issues (SELECT)
              end
            end
          end

          def reaction_count
            return @_reaction_count if defined?(@_reaction_count)

            @_reaction_count = with_read do
              subjects_and_ids = Hash.new { |h, k| h[k] = [] }

              legacy_reaction_subject_ids = user.reactions.where(content: :heart, subject_type: LEGACY_REACTION_SUBJECT_TYPES).pluck(
                :subject_type,
                :subject_id,
              ).each do |type, id|
                subjects_and_ids[type] << id
              end
              ::Reactable::SUBJECT_TYPES_WITH_SEPARATE_REACTION_MODELS.to_a.concat(%w[Discussion DiscussionComment]).each do |subject_type|
                association = "#{subject_type.underscore}_reactions"
                association_column = "#{subject_type.underscore}_id".to_sym
                subjects_and_ids[subject_type] = user.send(association).where(content: :heart).pluck(association_column)
              end

              types_with_repo_ids_and_subject_ids = {}
              repository_ids = Set.new

              subjects_and_ids.each do |type, ids|
                scope = type.constantize.where(id: ids)

                types_with_repo_ids_and_subject_ids[type] = if type == "RepositoryAdvisoryComment"
                  advisory_ids_and_comment_ids = scope.pluck(:repository_advisory_id, :id)
                  advisory_ids_and_repo_ids = RepositoryAdvisory.
                    where(id: advisory_ids_and_comment_ids.map(&:first)).
                    pluck(:id, :repository_id).
                    to_h

                  advisory_ids_and_comment_ids.map do |advisory_id, comment_id|
                    [advisory_ids_and_repo_ids[advisory_id], comment_id]
                  end
                elsif type == "DiscussionPost" || type == "DiscussionPostReply"
                  # DiscussionPost and DiscussionPostReply records are always
                  # private in the context of achievements
                  ids.map { |id| [:private, id] }
                else
                  scope.pluck(:repository_id, :id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
                end

                repository_ids += types_with_repo_ids_and_subject_ids[type].filter_map do |repo_id, _|
                  repo_id unless repo_id == :private
                end
              end

              public_repository_ids =
                Repository.where(id: repository_ids).public_scope.pluck(:id).to_set

              eligible_public_subject_ids = types_with_repo_ids_and_subject_ids.values.flat_map do |repo_ids_and_subject_ids|
                repo_ids_and_subject_ids.filter_map do |id, subject_id|
                  subject_id if id.in?(public_repository_ids)
                end
              end

              eligible_private_and_public_subject_ids = types_with_repo_ids_and_subject_ids.values.flat_map do |repo_ids_and_subject_ids|
                repo_ids_and_subject_ids.filter_map(&:second)
              end

              {
                public_only_count: eligible_public_subject_ids.size,
                private_and_public_count: eligible_private_and_public_subject_ids.size,
              }
            end
          end
        end
      end
    end
  end
end
