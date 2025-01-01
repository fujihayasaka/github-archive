class CreateMemexProjectElasticsearchConsistency < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Memexes)
  def change
    create_table :memex_project_elasticsearch_consistency, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column      :memex_project_id,    "bigint(20)", null: false, unsigned: true
      t.column      :consistency,         :decimal, precision: 5, scale: 2, null: false
      t.column      :evaluated_at,        :datetime, precision: 6
      t.column      :repair_started_at,   :datetime, precision: 6
      t.column      :repair_finished_at,  :datetime, precision: 6
      t.timestamps

      t.index :memex_project_id, unique: true
      t.index :consistency
      t.index :repair_started_at
    end
  end
end
