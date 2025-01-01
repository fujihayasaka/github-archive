class CreateEnterpriseTeamOrganizationMappings < ActiveRecord::Migration[7.2]
  def change
    create_table :enterprise_team_organization_mappings, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :enterprise_team_id, :bigint, unsigned: true, null: false
      t.column :organization_id, :bigint, unsigned: true, null: false
      t.column :team_id, :bigint, unsigned: true, null: true
      t.column :status, "enum('unsynced', 'partial', 'synced', 'failed')", null: false, default: :unsynced
      t.datetime :created_at, null: false, precision: 6
      t.datetime :updated_at, null: false, precision: 6
      t.datetime :synced_at, null: true, precision: 6, default: nil
      t.index [:enterprise_team_id, :organization_id], unique: true
      t.index :team_id, unique: true
    end
  end
end
