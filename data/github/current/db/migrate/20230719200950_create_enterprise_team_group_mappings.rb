# typed: true
class CreateEnterpriseTeamGroupMappings < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    create_table :enterprise_team_group_mappings, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column   :enterprise_team_id, :bigint, unsigned: true, null: false
      t.column   :external_group_id, :bigint, unsigned: true, null: false
      t.datetime :created_at, null: false, precision: 6
      t.datetime :updated_at, null: false, precision: 6
      t.datetime :deleted_at, null: true, default: nil, precision: 6
      t.index    [:enterprise_team_id, :external_group_id], unique: true
    end
  end
end
