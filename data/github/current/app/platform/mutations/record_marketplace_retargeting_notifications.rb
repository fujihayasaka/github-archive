# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class RecordMarketplaceRetargetingNotifications < Platform::Mutations::Base
      description "Record that Marketplace retargeting notification emails were sent"
      visibility :internal

      allow_anonymous_viewer true

      minimum_accepted_scopes ["repo"]

      argument :user_id, Integer, "The database id of user who was notified", required: true
      argument :sent_at, Scalars::DateTime, "The timestamp the notification was sent", required: true

      field :records_processed, Integer, "The number of order previews updated", null: true

      def resolve(**inputs)
        user = Loaders::ActiveRecord.load(::User, inputs[:user_id]).sync

        { records_processed: T.must(user).marketplace_order_previews.update_all(email_notification_sent_at: inputs[:sent_at]) }
      end
    end
  end
end
