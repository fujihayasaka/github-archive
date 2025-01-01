# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class SubscribeToCopilotLimited < Platform::Mutations::Base
      description "Subscribes a user to Copilot Free (limited)."

      minimum_accepted_scopes ["user"]

      required_capabilities [:access_copilot_limited_graphql_api]

      field :copilot_limited_user, Platform::Objects::CopilotLimitedUser, null: true, description: "The Copilot Free user."
      field :subscribed, Boolean, null: true, description: "Whether or not the user was subscribed to Copilot Free within this mutation."

      def self.async_api_can_modify?(permission)
        permission.access_allowed?(
          :update_user,
          resource: permission.viewer,
          current_org: nil,
          current_repo: nil,
          allow_integrations: false,
          allow_user_via_granular_actor: false
        )
      end

      def resolve(**inputs)
        viewer = context[:viewer]

        unless viewer.feature_flag_enabled?(:copilot_free_mobile, default: false)
          raise Errors::Unprocessable.new("Viewer does not have Copilot Free on Mobile enabled.")
        end

        if viewer.has_any_trade_restrictions?
          raise Errors::Unprocessable.new(
            ::TradeControls::Notices.notice_as_plaintext(:api_user_account_restricted_generic)
          )
        end

        limited_user = Copilot::LimitedUser.for_subscribed_user(viewer)

        if limited_user.present?
          return {
            copilot_limited_user: limited_user,
            subscribed: false,
          }
        end

        copilot_user = Copilot::User.new(viewer)
        result = copilot_user.subscribe_limited_user

        raise Errors::Unprocessable.new(result.error.message) unless result.ok?

        {
          copilot_limited_user: copilot_user.limited_user,
          subscribed: true,
        }
      end
    end
  end
end
