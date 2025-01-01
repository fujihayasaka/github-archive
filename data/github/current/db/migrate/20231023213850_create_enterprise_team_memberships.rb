# typed: true
class CreateEnterpriseTeamMemberships < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    create_table :enterprise_team_memberships, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column   :enterprise_team_id, :bigint, unsigned: true, null: false
      t.column   :user_id, :bigint, unsigned: true, null: false
      t.datetime :created_at, null: false, precision: 6
      t.datetime :updated_at, null: false, precision: 6
      t.index    [:enterprise_team_id, :user_id], unique: true
    end
  end
end
