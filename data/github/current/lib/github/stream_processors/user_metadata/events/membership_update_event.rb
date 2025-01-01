# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module UserMetadata
      module Events
        class MembershipUpdateEvent < UserMetadataEvent
          SKIP_REASON = "MembershipUpdate for an unmonitored team"

          # Teams this job monitors correspond to employees, bounty hunters, campus
          # experts, and stars. None of these are present on enterprise so we can skip everything.
          def skip?
            GitHub.multi_tenant_enterprise? || !team_update? || !processor.monitored_team?(team_id)
          end

          def skip_reason
            SKIP_REASON
          end

          def users
            user_id = message.value.dig(:user, :id)
            with_read { User.where(id: user_id) }
          end

          def team_id
            message.value.dig(:group_id)
          end

          private

          def team_update?
            context = message.value.dig(:context)

            GitHub.logger.info(
              "code.namespace" => "UserMetadata::Events::MembershipUpdateEvent",
              "code.function" => "team_update?",
              "gh.profiles.context" => context,
              "gh.team.id" => team_id,
            )

            context == :TEAM && team_id.present?
          end
        end
      end
    end
  end
end
