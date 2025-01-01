# typed: false
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Achievements
      module Events
        class AchievementEvent
          include Achievements::ProcessingMethods

          ORGANIZATION_IDS_BLOCKED_FROM_ACHIEVEMENT_TRACKING = [
            93784371, # community
          ].freeze

          IGNORED_LOGINS = %w(ghost).freeze
          IGNORED_USER_SKIP_MESSAGE = "User is ignored."
          USER_OR_ORG_OPTED_OUT_SKIP_MESSAGE =
            "User or org has opted out of achievements for their private repositories."
          ORGANIZATION_BLOCKED_FROM_ACHIEVEMENT_TRACKING_SKIP_MESSAGE =
            "Organization is blocked from achievements."

          def self.from(message, processor)
            schema = message.schema.gsub(/\Ahydro\.schemas\./, "")

            processor.class::EVENT_CLASSES.each do |event_class|
              return event_class.new(message, processor) if event_class.matches?(schema)
            end

            UnknownEvent.new(message, processor)
          end

          attr_reader :message, :processor

          def initialize(message, processor)
            @message = message
            @processor = processor
          end

          def self.matches?(schema)
            matching_schema.any? { |pattern| pattern.match?(schema) }
          end

          def self.matching_schema
            self::MATCHING_SCHEMA
          end

          def skip?
            !skip_reason.nil?
          end

          def skip_reason
            if ignored_user?
              IGNORED_USER_SKIP_MESSAGE
            elsif organization_blocked_from_achievement_tracking?
              ORGANIZATION_BLOCKED_FROM_ACHIEVEMENT_TRACKING_SKIP_MESSAGE
            elsif user_or_org_opted_out?
              USER_OR_ORG_OPTED_OUT_SKIP_MESSAGE
            end
          end

          def name
            self.class.name.demodulize
          end

          def recalculation?
            false
          end

          def ignored_user?
            user_type == :BOT ||
              IGNORED_LOGINS.include?(user_login) ||
              User::ContributionsDependency::LARGE_BOT_ACCOUNTS.include?(user_id) ||
              user&.spammy?
          end

          def user_or_org_opted_out?
            !repository_public? && repository_owner&.
              profile_settings&.
              all_private_projects_opted_out_of_achievements_tracking?
          end

          def organization_blocked_from_achievement_tracking?
            ORGANIZATION_IDS_BLOCKED_FROM_ACHIEVEMENT_TRACKING.include?(repository_owner_id)
          end

          def user
            return @_user if defined?(@_user)

            @_user = with_read { User.find_by(id: user_id) }
          end

          # Internal: Return a path of Symbols used to find a github.v1.entities.User entity within the triggering
          # Hydro message that corresponds logically to the (primary) user who would potentially earn the achievement.
          #
          # Defaults to the `:actor`. Override to return an alternate path if an `:author` or `:user` is desired
          # instead.
          #
          # Returns an Array of Symbols describing a sequence of keys within the `MATCHING_SCHEMA` Hydro messages that
          # ends in a user entity.
          def user_message_path
            [:actor]
          end

          def user_id
            return @_user_id if defined?(@_user_id)

            @_user_id = message.value.dig(*user_message_path, :id)
          end

          def user_login
            return @_user_login if defined?(@_user_login)

            @_user_login = message.value.dig(*user_message_path, :login)
          end

          def user_type
            return @_user_type if defined?(@_user_type)

            @_user_type = message.value.dig(*user_message_path, :type)
          end

          def actor_id
            message.value.dig(:actor, :id)
          end

          def actor
            return @_actor if defined?(@_actor)

            @_actor = with_read { User.find_by(id: actor_id) }
          end

          def achievable_slug
            achievable_class.slug
          end

          def current_achievement_tier(subject_user: user, subject_visibility: visibility)
            subject_user.achievement_tier_for(achievable_class, visibility: subject_visibility)
          end

          def next_achievement_tier(subject_user: user, subject_visibility: visibility)
            current_achievement_tier(
              subject_user: subject_user,
              subject_visibility: subject_visibility,
            ) + 1
          end

          def next_achievement_tier_threshold(subject_user: user, subject_visibility: visibility)
            next_tier = achievable_class.tier(
              next_achievement_tier(
                subject_user: subject_user,
                subject_visibility: subject_visibility,
              ),
            )

            if next_tier.valid?
              next_tier.threshold
            else
              current_achievement_tier_threshold(
                subject_user: subject_user,
                subject_visibility: subject_visibility,
              )
            end
          end

          def current_achievement_tier_threshold(subject_user: user, subject_visibility: visibility)
            current_tier = achievable_class.tier(
              current_achievement_tier(
                subject_user: subject_user,
                subject_visibility: subject_visibility,
              ),
            )

            if current_tier.valid?
              current_tier.threshold
            else
              nil
            end
          end

          def achievement_progression(subject_user: user)
            with_read { subject_user.achievement_progression_for(achievable_class) }
          end

          def achievable_class
            self.class::ACHIEVABLE_CLASS
          end

          def already_has_highest_tier_achievement?(
            subject_user: user,
            subject_visibility: visibility
          )
            subject_user.has_achievement_with_tier?(
              achievable_class,
              achievable_class.highest_tier,
              visibility: subject_visibility,
            )
          end

          def already_has_both_highest_tier_achievements?(subject_user: user)
            subject_user.achievements
              .with_slug(achievable_class.slug)
              .with_tier(achievable_class.highest_tier)
              .size == 2
          end

          def repository_visibility
            message.value.dig(:repository, :visibility)
          end

          def repository_public?
            repository_visibility == :PUBLIC
          end

          def repository_owner
            with_read { User.find_by(id: repository_owner_id) }
          end

          def repository_owner_id
            message.value.dig(:repository, :owner_id, :value)
          end

          def public?
            visibility == :PUBLIC
          end

          def wait_for_replication?
            false
          end

          private

          # Simple wrapper for connecting to read pool for read operations only.
          def with_read
            ActiveRecord::Base.connected_to(role: :reading) do
              yield
            end
          end
        end
      end
    end
  end
end
