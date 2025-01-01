# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module UserMetadata
      class UserTeamMembershipProcessor < UserMetadataBaseProcessor
        include GitHub::FeatureFlag

        HYDRO_TARGET_PROCESSOR_NAME = :USER_TEAM_MEMBERSHIP.freeze
        DEFAULT_GROUP_ID = "user_team_membership_processor"
        DEFAULT_SUBSCRIBE_TO = [/github.v1.MembershipUpdate\Z/].freeze

        # This processor will get skipped on multi tenant enterprise,
        # (see lib/github/stream_processors/user_metadata/events/membership_update_event.rb)
        # but we still want to mark it as exempt.
        #
        # This processor is exempt from the tenant context requirement.
        # It queries for existing team memberships directly from the user's associations,
        # and thus we don't have to worry about scope leakage.
        exempt_from_tenant_context_requirement

        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO

          self.metric_prefix = "user_metadata_processor.user_team_membership"
          self.dead_letter_topic = "user_metadata.v0.UserTeamMembership.DeadLetter"
        end

        def monitored_team?(team_id)
          team_id_and_attribute_mapping.key?(team_id)
        end

        # Public: User metadata that this stream processor should update for a given user.
        #
        # event - the UserMetadataEvent currently being processed
        # user  - a User with metadata affected by the event being processed
        #
        # Returns a Hash of metadata key/value pairs to update for the specified user.
        def metadata_updates(event, user)
          # Could handle a recalculation event here by updating
          # all team metadata attributes.

          team_id = event.team_id
          metadata_attr = metadata_attribute(team_id)

          {
            metadata_attr => belongs_to_team?(user, team_id)
          }
        end

        private

        def metadata_attribute(team_id)
          team_id_and_attribute_mapping[team_id]
        end

        def belongs_to_team?(user, team_id)
          with_read { user.teams.where(id: team_id).exists? }
        end

        def team_id_and_attribute_mapping
          @_team_id_and_attribute_mapping ||= {
            GitHub::FeatureFlag.employees_team.id => :is_staff,
            GitHub::FeatureFlag.campus_experts_badge_team.id => :is_campus_expert,
            GitHub::FeatureFlag.bounty_hunters_team.id => :is_bounty_hunter,
            GitHub::FeatureFlag.github_stars_team.id => :is_github_star
          }
        end
      end
    end
  end
end
