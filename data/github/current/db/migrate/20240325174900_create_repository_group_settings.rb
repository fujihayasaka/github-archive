# typed: true

class CreateRepositoryGroupSettings < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    create_table :repository_group_settings, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :repository_group_id, unsigned: true, null: false
      t.string :type, limit: 64, null: false
      t.json   :value, null: false
      t.bigint :orchestration_id, unsigned: true, null: true

      t.timestamps

      t.index [:repository_group_id, :type], unique: true, name: "index_repository_group_settings_group_id_type"
    end
  end
end
