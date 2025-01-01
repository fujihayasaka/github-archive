
# typed: true
# frozen_string_literal: true

class CreateStarredCustomCopilotsTable < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def up
    create_table :starred_custom_copilots, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :user_id, unsigned: true, null: false
      t.bigint :custom_copilot_id, unsigned: true, null: false
      t.timestamps

      t.index [:user_id, :custom_copilot_id], unique: true
    end
  end

  def down
    drop_table :starred_custom_copilots
  end
end
