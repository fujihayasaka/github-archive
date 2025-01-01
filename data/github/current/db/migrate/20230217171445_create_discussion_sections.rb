# typed: true

class CreateDiscussionSections < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Discussions)

  def change
    create_table :discussion_sections, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|

      t.bigint :repository_id, unsigned: true, null: false
      t.column :emoji, "varchar(44)", null: false, default: ":hash:"
      t.column :name, "varchar(40)", null: false
      t.column :slug, "varchar(40)", null: false

      t.timestamps

      t.index :repository_id
    end
  end
end
