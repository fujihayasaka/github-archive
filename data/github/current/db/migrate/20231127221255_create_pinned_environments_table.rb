class CreatePinnedEnvironmentsTable < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    create_table :pinned_environments, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :repository_id, null: false, unsigned: true
      t.bigint :environment_id, null: false, unsigned: true
      t.integer :position, unsigned: true, null: false, default: 1
      t.datetime :created_at, null: false, precision: 6

      t.index [:repository_id, :environment_id], unique: true, name: "index_pinned_environments_on_repository_id_and_environment_id"
      t.index [:repository_id, :position], name: "index_pinned_environments_on_repository_id_and_position"
    end
  end
end
