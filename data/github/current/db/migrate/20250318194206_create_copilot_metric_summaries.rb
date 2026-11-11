# typed: true
# frozen_string_literal: true

class CreateCopilotMetricSummaries < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    create_table :copilot_metric_summaries, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :owner_id, null: false, unsigned: true
      t.string :owner_type, null: false, limit: 255
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.integer :total_seats, null: false
      t.integer :active_seats, null: false
      t.integer :inactive_seats, null: false
      t.integer :dormant_seats, null: false
      t.timestamps

      t.index [:owner_id, :owner_type, :start_date, :end_date], name: "index_cms_on_owner_and_dates", unique: true
    end
  end
end
