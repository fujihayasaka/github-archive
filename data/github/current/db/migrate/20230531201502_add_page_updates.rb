# typed: true
class AddPageUpdates < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    create_table :page_updates, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :page_id, null: false, unsigned: true
      t.column :event, :tinyint, unsigned: true, null: false, comment: "the type of event (update, destroy)"
      t.datetime :created_at, precision: 6, null: false
      t.datetime :updated_at, precision: 6, null: false
      t.index [:page_id]
    end
  end
end
