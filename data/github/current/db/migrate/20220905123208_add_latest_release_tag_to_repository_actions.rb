# typed: true

class AddLatestReleaseTagToRepositoryActions < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    change_table :repository_actions, bulk: true do |t|
      t.column :latest_release_tag, :binary, limit: 1024, null: true
      t.change :id, :bigint, unsigned: true
      t.change :repository_id, :bigint, unsigned: true
    end
  end
end
