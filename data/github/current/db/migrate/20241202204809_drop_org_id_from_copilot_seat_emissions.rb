# typed: true
# frozen_string_literal: true

class DropOrgIdFromCopilotSeatEmissions < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_seat_emissions, bulk: true do |t|
      t.remove_references :organization, null: true, index: true, comment: "The organization that this seat emission is for"
    end
  end
end
