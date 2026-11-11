# typed: true
# frozen_string_literal: true

class AddJsonPayloadToVisualStudioSubscriptionEvents < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Billing)

  def change
    change_table :vss_subscription_events, bulk: true do |t|
      t.change :id, :bigint, unsigned: true
      t.json :parsed_payload
      t.string :subscription_id, limit: 36, as: "parsed_payload->>'$.SubscriptionGuid'", stored: true
      t.string :last_modified_date, as: "parsed_payload->>'$.Timestamps.LastModifiedDate'", stored: true
      t.index [:subscription_id, :last_modified_date]
    end
  end
end
