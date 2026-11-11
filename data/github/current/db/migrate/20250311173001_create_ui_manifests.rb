# rubocop:disable GitHub/UseBigintUnsignedPrimaryKeys
# typed: true

class CreateUIManifests < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Ballast)

  def change
    create_table :ui_manifests, id: false, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :target, null: false, primary_key: true
      t.string :sha, null: false, index: true
      t.json :manifest, null: false

      t.timestamps
    end
  end
end
