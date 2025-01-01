# typed: true
class ReplaceTypeWithReleaseTypeMemexReleases < ActiveRecord::Migration[7.1]

  self.use_connection_class(ApplicationRecord::Memex)

  def up

    change_table :memex_releases, bulk: true do |t|
      t.remove_index [:type], name: "index_memex_releases_on_type"
      t.remove :type

      t.column :release_type, "tinyint(4)", null: false, index: true
    end
  end

  def down
    change_table :memex_releases, bulk: true do |t|
      t.remove_index [:release_type], name: "index_memex_releases_on_type"
      t.remove :release_type

      t.column :type, "tinyint(4)", null: false, index: true
    end
  end
end
