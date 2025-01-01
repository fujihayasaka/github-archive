# typed: true

class PushesTableIndexAndColumnOptimization < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::RepositoriesPushes)

  def up
    change_table :pushes, bulk: true do |t|
      t.remove :forced

      t.change :created_at, "datetime", null: false
      t.change :pushed_at, "datetime(6)", null: false
      t.change :push_type, "tinyint(3)", unsigned: true, null: false

      t.remove_index name: "index_pushes_on_repository_id_and_pusher_id_and_created_at"

      t.index [:repository_id, :pushed_at], name: "index_pushes_on_repository_id_and_pushed_at"
      t.index [:repository_id, :push_type, :pushed_at], name: "index_pushes_on_repository_id_and_push_type_and_pushed_at"
    end
  end

  def down
    change_table :pushes, bulk: true do |t|
      t.boolean :forced, null: true

      t.change :created_at, "datetime", null: true
      t.change :pushed_at, "datetime(6)", null: true
      t.change :push_type, "tinyint(3)", unsigned: true, null: true

      t.remove_index name: "index_pushes_on_repository_id_and_pushed_at"
      t.remove_index name: "index_pushes_on_repository_id_and_push_type_and_pushed_at"

      t.index [:repository_id, :pusher_id, :created_at],
        name: "index_pushes_on_repository_id_and_pusher_id_and_created_at"
    end
  end
end
