# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module UserMetadata
      class AchievementProcessor < UserMetadataBaseProcessor
        HYDRO_TARGET_PROCESSOR_NAME = :ACHIEVEMENTS.freeze
        DEFAULT_GROUP_ID = "achievement_processor"
        DEFAULT_SUBSCRIBE_TO = [
          /github\.achievements\.v1\.AchievementUnlock\Z/,
          /github\.user_metadata\.v1\.Recalculation\Z/,
        ]

        # Processing achievements should be exempt from the tenant context requirement.
        # For the time being achievements are not going to be enabled on proxima.
        # Further, this job queries the achievements for a given user directly, and isn't subject to scope leakage.
        exempt_from_tenant_context_requirement

        # Public: Configure the Hydro processor
        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO

          self.metric_prefix = "user_metadata_processor.achievement"
        end

        # Public: User metadata that this stream processor should update for a given user.
        #
        # event - the UserMetadataEvent currently being processed, in this case an AchievementEvent
        # user  - a User with metadata affected by the event being processed
        #
        # Returns a Hash of metadata key/value pairs to update for the specified user.
        def metadata_updates(event, user)
          updates = {}
          pub_achievements, priv_achievements = all_achievements_for(event, user)

          if event.recalculation? || event.public?
            updates[:achievements_public_count] = pub_achievements.size
            updates[:achievement_public_slugs] = achievement_slugs_and_tiers_from(pub_achievements)
            updates[:has_unseen_public_achievement] = pub_achievements.any?(&:unseen?)
          end

          if event.recalculation? || event.private?
            updates[:achievements_private_count] = priv_achievements.size
            updates[:achievement_private_slugs] = achievement_slugs_and_tiers_from(priv_achievements)
            updates[:has_unseen_private_achievement] = priv_achievements.any?(&:unseen?)
          end

          updates
        end

        private

        def all_achievements_for(event, user)
          with_read do
            if event.recalculation?
              user.all_highest_tier_achievements
            elsif event.public?
              [user.highest_tier_achievements(visibility: :PUBLIC), []]
            elsif event.private?
              [[], user.highest_tier_achievements(visibility: :PRIVATE)]
            end
          end
        end

        # Private: Encode the user's currently earned, highest-tier Achievements as a comma-separated list.
        #
        # achievements - An Array of Achievements with unique Achievables (only the highest tier of each), ordered
        #   with the most recently earned first.
        #
        # Returns a String to be interpreted by UserMetadata#achievables_and_tiers.
        def achievement_slugs_and_tiers_from(achievements)
          achievements.map(&:to_slug_and_tier).join(",")
        end
      end
    end
  end
end
