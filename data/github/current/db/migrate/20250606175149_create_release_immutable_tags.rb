# typed: true
# frozen_string_literal: true

class CreateReleaseImmutableTags < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    create_table :release_immutable_tags, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :repository_id, :bigint, unsigned: true, null: false
      t.column :release_id, :bigint, unsigned: true, null: false
      t.column :tag_name, "varbinary(1024)", null: false
      t.timestamps

      t.index [:repository_id, :tag_name], unique: true
      t.index :release_id, unique: true
    end
  end
end
