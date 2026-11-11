# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class BlockActions < Platform::Mutations::Base
      description "Disable Actions access for a user via Actions::Invocation.block and queue for spammy review"

      visibility :internal
      minimum_accepted_scopes ["site_admin"]

      argument :user_id, ID, "The global relay id of the user or org to block actions invocation for and queue for review.", required: true
      argument :reason, String, "Reason for disabling the repo", required: true

      field :id, String, "Global relay id of the account that was blocked", null: true

      def self.async_api_can_modify?(permission, **inputs)
        viewer_is_site_admin?(permission.viewer, name)
      end

      def resolve(user_id:, reason:, **inputs)
        viewer = @context[:viewer]

        begin
          repo_owner = Platform::Helpers::NodeIdentification.async_typed_object_from_id([Objects::User, Objects::Organization], user_id, @context).then do |repo_owner|
            Actions::Invocation.block(actor: repo_owner, staff_actor: viewer)

            # Send actions abuse block to queue for spammy review
            payload = {
              billing_plan_owner: {
                id: repo_owner.global_relay_id,
                type: repo_owner.type.to_s,
                created_at: repo_owner.created_at,
                plan: repo_owner.plan.to_s,
              },
              blocking_reason: reason
            }

            result = GitHub.hydro_publisher.publish(
              payload,
              schema: "security_api.v1.ActionsAbuseBlock",
              topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 } # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
            )

            fields = {
              "gh.actions.actor.global_id" => repo_owner.global_relay_id,
              "blocking_reason" => reason,
              "success" => result.success?,
              "error" => result.error
            }

            GitHub.logger.info("security_api.v1.ActionsAbuseBlock emitted", fields)

            {
              id: repo_owner.global_relay_id,
            }
          end
        end
      end
    end
  end
end
