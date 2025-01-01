# typed: true
class CreateMemexReleases < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Memex)

  def change
    create_table :memex_releases, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :sha, limit: 40, null: false, index: { unique: true }
      t.string :version, limit: 50, null: false, index: { unique: true }
      t.column :branch, "varbinary(1024)", null: false, index: true
      t.column :type, "tinyint(4)", null: false, index: true

      t.timestamps
    end

  end
end
