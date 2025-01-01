# typed: true
# frozen_string_literal: true

class CreateUserDashboardTeams < ActiveRecord::Migration[7.1]
  def change
    create_table :user_dashboard_teams, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :user_dashboard_id, :bigint, unsigned: true, null: false
      t.column :team_id, :bigint, unsigned: true, null: false
    end

    add_index :user_dashboard_teams, [:user_dashboard_id, :team_id], unique: true
  end
end
