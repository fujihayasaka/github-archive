# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class NotificationStatus < Platform::Enums::Base
      description "The possible states of a notification."
      required_capabilities [:mobile_only_schema_mask, :access_internal_graphql_notifications]

      value "READ", "A notification is read", value: "inbox_read"
      value "UNREAD", "A notification is unread", value: "inbox_unread"
      value "ARCHIVED", "A notification is archived", value: "archived"
      value "DONE", "A notification is done", value: "archived"
    end
  end
end
