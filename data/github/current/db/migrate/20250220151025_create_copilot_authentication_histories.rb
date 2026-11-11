# typed: true
# frozen_string_literal: true

class CreateCopilotAuthenticationHistories < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    create_table :copilot_authentication_histories, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :copilot_seat_id, unsigned: true, null: false, comment: "Specific Copilot Seat for this authentication"
      t.date :authentication_date, null: false, comment: "Date of authentication"
      t.json :authentication_details, null: false, comment: "Details of the authentication"
      t.timestamps

      t.index [:copilot_seat_id, :authentication_date], name: "index_cahis_on_seat_and_date", unique: true
    end
  end
end
