# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class NotificationThreadSubscriptionListType < Platform::Enums::Base
      mobile_only true
      required_capabilities [:access_internal_graphql_notifications]

      description "The possible types of notification thread subscription lists."

      value "REPOSITORY", "Repository", value: "Repository"
      value "TEAM", "Team", value: "Team"
    end
  end
end
