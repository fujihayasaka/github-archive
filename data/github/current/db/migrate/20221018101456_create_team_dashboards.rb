# typed: true
# frozen_string_literal: true

class CreateTeamDashboards < ActiveRecord::Migration[7.1]
  def change
    create_table :team_dashboards, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :team_id, unsigned: true, null: false
      t.timestamps

      t.index :team_id, unique: true
    end
  end
end
