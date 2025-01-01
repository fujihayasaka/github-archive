# typed: true

class CreateEnterpriseTeams < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    create_table :enterprise_teams, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column   :business_id, :bigint, unsigned: true, null: false
      t.column   :name, "varchar(255)", null: false
      t.column   :slug, "varchar(255)", null: false
      t.datetime :created_at, null: false, precision: 6
      t.datetime :updated_at, null: false, precision: 6
      t.datetime :deleted_at, null: true, default: nil, precision: 6
      t.index    [:business_id, :slug], unique: true
    end
  end
end
