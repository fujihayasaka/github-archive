# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module UserMetadata
      class ProBadgeProcessor < UserMetadataBaseProcessor
        include FeatureFlag

        EMPLOYEES_ORG_AND_TEAM = FeatureFlag::EMPLOYEES_ORG_AND_TEAM_NAME.freeze
        HYDRO_TARGET_PROCESSOR_NAME = :PRO_BADGE.freeze
        DEFAULT_GROUP_ID = "pro_badge_processor"
        DEFAULT_SUBSCRIBE_TO = [
          /github\.v1\.UserBehavior\Z/,
          /github.v1.MembershipUpdate\Z/,
        ].freeze

        # This processor is exempt from the tenant context requirement.
        # The underlying `user.can_have_pro_badge?` method checks the user's
        # employee status and then looks at their `plan`. Both of these operations
        # aren't subject to scope leakage.
        #
        # In reality this processor should get skipped on proxima, see
        # MembershipUpdateEvent#skip? where we check to see if the user is on the employee_team,
        # and that team is only on github.com.
        exempt_from_tenant_context_requirement

        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO

          self.metric_prefix = "user_metadata_processor.pro_badge"
          self.dead_letter_topic = "user_metadata.v0.ProBadge.DeadLetter"
        end

        def monitored_team?(team_id)
          team_id == employee_team_id
        end

        # Public: User metadata that this stream processor should update for a given user.
        #
        # event - the UserMetadataEvent currently being processed
        # user  - a User with metadata affected by the event being processed
        #
        # Returns a Hash of metadata key/value pairs to update for the specified user.
        def metadata_updates(event, user)
          {
            has_pro_badge: has_pro_badge?(user)
          }
        end

        private

        def employee_team_id
          return @employee_team_id if defined?(@employee_team_id)

          @employee_team_id = with_read do
            org_login = EMPLOYEES_ORG_AND_TEAM.first
            team_slug = EMPLOYEES_ORG_AND_TEAM.last
            if org = Organization.find_by(login: org_login)
              org.teams.find_by(slug: team_slug)&.id
            end
          end
        end

        def has_pro_badge?(user)
          with_read { user.can_have_pro_badge? }
        end
      end
    end
  end
end
