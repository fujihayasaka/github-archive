# typed: true
# frozen_string_literal: true

class CreateCopilotEntityMemberships < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    create_table :copilot_entity_memberships, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :user_id, unsigned: true, null: false
      t.bigint :entity_id, unsigned: true, null: false
      t.column :entity_type, :tinyint, unsigned: true, null: false, default: 0
      t.bigint :copilot_insights_activities_id, unsigned: true
      t.bigint :platform_insights_activities_id, unsigned: true

      t.timestamps

      t.index [:user_id, :entity_id, :entity_type], unique: true, name: "index_copilot_entity_memberships_on_user_and_entity"
    end
  end
end
