# typed: true
# frozen_string_literal: true

class AddCreatorToCustomCopilots < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def up
    change_table :custom_copilots, bulk: true do |t|
      t.bigint :creator_id, null: true, unsigned: true, comment: "The ID of the user who created the custom copilot."
      t.index [:creator_id], name: "index_custom_copilots_on_creator_id"
    end
  end

  def down
    change_table :custom_copilots, bulk: true do |t|
      t.remove_index name: "index_custom_copilots_on_creator_id"
      t.remove :creator_id
    end
  end
end
