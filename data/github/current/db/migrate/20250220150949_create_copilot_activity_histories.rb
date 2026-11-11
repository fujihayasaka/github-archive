# typed: true
# frozen_string_literal: true

class CreateCopilotActivityHistories < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    create_table :copilot_activity_histories, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :copilot_seat_id, unsigned: true, null: false, comment: "Specific Copilot Seat for this activity"
      t.date :activity_date, null: false, comment: "Date of activity"
      t.json :activity_details, null: false, comment: "Details of the activity"
      t.timestamps

      # We are going to most often query by copilot_seat_id and activity_date, so we add an index for faster lookups
      t.index [:copilot_seat_id, :activity_date], name: "index_cah_on_seat_and_date", unique: true
    end
  end
end
