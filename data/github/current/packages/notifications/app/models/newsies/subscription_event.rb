# typed: true
# frozen_string_literal: true

module Newsies
  class SubscriptionEvent < ApplicationRecord::Domain::Notifications
    self.table_name = :notification_subscription_events
    self.utc_datetime_columns = [:created_at, :updated_at]

    belongs_to :subscription, polymorphic: true
  end
end
