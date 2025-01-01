class CreateMemexProjectStatuses < ActiveRecord::Migration[7.2]

  self.use_connection_class(ApplicationRecord::Domain::Memexes)

  def change
    create_table :memex_project_statuses, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :creator_id, "bigint(20)", null: false, unsigned: true
      t.column :memex_project_id, "bigint(20)", null: false, unsigned: true

      t.column :body, :text, null: false

      # status value will contain status_id, start_date, and target_date
      t.column :status_value, :json, null: false

      t.timestamps
    end
  end
end
