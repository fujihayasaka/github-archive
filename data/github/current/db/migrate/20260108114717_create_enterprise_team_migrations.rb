# typed: true
# frozen_string_literal: true

class CreateEnterpriseTeamMigrations < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Accounts)

  def change
    create_table :enterprise_team_migrations, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :enterprise_team_id, :bigint, unsigned: true, null: false
      t.column :team_id, :bigint, unsigned: true, null: false
      t.column :migration_status, :tinyint, unsigned: true, null: false, default: 0

      t.timestamps

      t.index :enterprise_team_id, unique: true, name: "index_enterprise_team_migrations_on_enterprise_team_id"
      t.index :team_id, unique: true, name: "index_enterprise_team_migrations_on_team_id"
    end
  end
end
