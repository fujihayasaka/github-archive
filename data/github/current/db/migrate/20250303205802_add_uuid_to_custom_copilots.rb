# typed: true

class AddUUIDToCustomCopilots < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    # add a UUID column to the custom_copilots table
    # for now it will be nullable until we can run the transition to backfill it
    add_column :custom_copilots, :uuid, :string, limit: 36, null: true
  end
end
