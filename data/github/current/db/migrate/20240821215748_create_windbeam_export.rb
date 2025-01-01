class CreateWindbeamExport < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Windbeam)

  def change
    create_table :windbeam_exports, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :user_id, null: false, unsigned: true
      t.integer :state, null: false, default: 0
      t.text :azure_url
      t.text :request_id
      t.datetime :azure_url_updated_at, precision: 6

      t.timestamps precision: 6
    end
  end
end
