# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class NotificationsList < Platform::Unions::Base
      description "The parent object that the notification thread's subject belongs to."
      required_capabilities [:mobile_only_schema_mask, :access_internal_graphql_notifications]

      possible_types(
        Objects::Organization,
        Objects::Repository,
        Objects::Team,
        Objects::User,
        Objects::Enterprise,
      )
    end
  end
end
