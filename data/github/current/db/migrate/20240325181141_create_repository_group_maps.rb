# typed: true

class CreateRepositoryGroupMaps < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    create_table :repository_group_maps, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :repository_group_id, unsigned: true, null: false
      t.bigint :repository_id, unsigned: true, null: false
      t.timestamps

      t.index [:repository_group_id, :repository_id], unique: true, name: "index_repository_group_maps_group_id_repository_id"
      t.index [:repository_id], unique: true, name: "index_repository_group_maps_repository_id"
    end
  end
end
