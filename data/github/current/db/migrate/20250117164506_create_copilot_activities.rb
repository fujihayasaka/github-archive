# typed: true
# frozen_string_literal: true

class CreateCopilotActivities < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    create_table :copilot_activities, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.references :copilot_seat, index: { unique: true }, null: false, comment: "Specific Copilot Seat for this activity"
      t.string :activity_details
      t.datetime :activity_at, null: false, precision: 6
      t.timestamps
    end
  end
end
