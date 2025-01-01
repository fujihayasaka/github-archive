# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ChangeUserStatus < Platform::Mutations::Base
      description "Update your status on GitHub."

      def self.async_api_can_modify?(permission, **inputs)
        permission.access_allowed?(:update_user, resource: permission.viewer,
                                   current_repo: nil, current_org: nil,
                                   allow_integrations: false, allow_user_via_granular_actor: false)
      end

      minimum_accepted_scopes ["user"]

      argument :emoji, String, "The emoji to represent your status. Can either be a native " \
                               "Unicode emoji or an emoji name with colons, e.g., :grinning:.",
        required: false
      argument :message, String, "A short description of your current status.",
        required: false
      argument :organization_id, ID, "The ID of the organization whose members will be allowed " \
                                     "to see the status. If omitted, the status will be " \
                                     "publicly visible.",
        required: false, loads: Objects::Organization
      argument :limited_availability, Boolean, "Whether this status should indicate you are not " \
                                               "fully available on GitHub, e.g., you are away.",
        required: false, default_value: false
      argument :expires_at, Scalars::DateTime, "If set, the user status will not be " \
                                               "shown after this date.",
        required: false

      field :status, Objects::UserStatus, "Your updated status.", null: true

      def resolve(emoji: nil, message: nil, limited_availability:, organization: nil, expires_at: nil)
        user = context[:viewer]
        status = ::UserStatus.set_for(user, emoji: emoji, message: message,
                                      org: organization, limited_availability: limited_availability,
                                      expires_at: expires_at)

        { status: status }
      end
    end
  end
end
