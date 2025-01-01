# typed: true

class RemoveAndAddIndexesToPushes < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::RepositoriesPushes)

  def up
    change_table :pushes, bulk: true do |t|
      t.remove_index name: "index_pushes_on_pusher_id"
      t.remove_index name: "index_pushes_on_repository_id_and_ref_and_created_at"

      t.index [:repository_id, :pusher_id, :pushed_at],
        name: "index_pushes_on_repository_id_and_pusher_id_and_pushed_at"
    end
  end

  def down
    change_table :pushes, bulk: true do |t|
      t.remove_index name: "index_pushes_on_repository_id_and_pusher_id_and_pushed_at"

      t.index [:pusher_id],
        name: "index_pushes_on_pusher_id"
      t.index [:repository_id, :ref, :created_at],
        name: "index_pushes_on_repository_id_and_ref_and_created_at"
    end
  end
end
