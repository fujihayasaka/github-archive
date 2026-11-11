# frozen_string_literal: true

class CreateAdvisoryAlertingEvents < ActiveRecord::Migration[7.0]
  def change
    create_table :advisory_alerting_events do |t|
      t.string :ghsa_id, limit: 19, null: false
      t.bigint :alerting_event_id, null: false
      t.datetime :processed_at
      t.datetime :finished_at
      t.integer :alert_count, default: 0, null: false
      t.integer :notification_count, default: 0, null: false

      t.timestamps
    end
  end
end
