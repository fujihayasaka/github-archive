# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class BlockActions < Platform::Mutations::Base
      description "Disable Actions access for a user via Actions::Invocation.block and queue for spammy review"

      visibility :internal
      minimum_accepted_scopes ["site_admin"]

      argument :user_id, ID, "The global relay id of the user to block actions invocation for and queue for review.", required: true, loads: Objects::User
      argument :reason, String, "Reason for disabling the repo", required: true

      # error_fields
      field :id, String, "Global relay id of the account that was blocked", null: true

      def self.async_api_can_modify?(permission, **inputs)
        viewer_is_site_admin?(permission.viewer, name)
      end

      def resolve(user:, reason:, **inputs)
        viewer = @context[:viewer]

        begin
          Actions::Invocation.block(actor: user, staff_actor: viewer)

          # Send actions abuse block to queue for spammy review
          payload = {
            billing_plan_owner: {
              id: user.global_relay_id,
              type: user.type.to_s,
              created_at: user.created_at,
              plan: user.plan.to_s,
            },
            blocking_reason: reason
          }

          result = GitHub.hydro_publisher.publish(
            payload,
            schema: "security_api.v1.ActionsAbuseBlock",
            topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 } # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
          )

          fields = {
            "gh.actions.actor.global_id" => user.global_relay_id,
            "blocking_reason" => reason,
            "success" => result.success?,
            "error" => result.error
          }

          GitHub.logger.info("security_api.v1.ActionsAbuseBlock emitted", fields)

          {
            id: user.global_relay_id
          }
        end
      end
    end
  end
end
