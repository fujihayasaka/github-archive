# typed: true
# frozen_string_literal: true

class CreateTeamSearchShortcuts < ActiveRecord::Migration[7.1]
  def change
    create_table :team_search_shortcuts, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :team_dashboard_id, unsigned: true, null: false
      t.bigint :priority, unsigned: true
      t.bigint :scoping_repository_id, unsigned: true
      t.string :name, limit: 1024, default: "", null: false
      t.integer :search_type, default: 0, null: false
      t.integer :icon, default: 0
      t.integer :color, default: 0
      t.mediumblob :compressed_query
      t.mediumblob :description
      t.timestamps

      t.index [:team_dashboard_id, :priority], unique: true
      t.index :scoping_repository_id
    end
  end
end
