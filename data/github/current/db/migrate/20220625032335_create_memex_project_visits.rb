# typed: true

class CreateMemexProjectVisits < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Memex)

  def change
    create_table :memex_project_visits, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :owner_id, "bigint(20)", null: false, unsigned: true
      t.column :owner_type, "varchar(30)", null: false
      t.column :viewer_id, "bigint(20)", null: false, unsigned: true
      t.column :memex_project_id, "bigint(20)", null: false, unsigned: true
      t.column :last_visited_at, :datetime, null: false, precision: 6

      t.index [:memex_project_id, :viewer_id], unique: true, name: :index_memex_project_visits_on_memex_project_id_and_viewer_id
      t.index [:viewer_id, :owner_id, :owner_type, :last_visited_at], name: :index_memex_project_visits_on_viewer_id_and_owner_and_updated_at
    end
  end
end
