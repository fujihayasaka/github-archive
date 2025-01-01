# typed: true
class RemoveRepoIdPathIndexFromWorkflows < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::RepositoriesActionsChecks)

  def up
    change_table :workflows, bulk: true do |t|
      t.remove_index [:repository_id, :path], name: "index_workflows_on_repository_id_and_path"
    end
  end

  def down
    change_table :workflows, bulk: true do |t|
      t.index [:repository_id, :path], unique: true, name: "index_workflows_on_repository_id_and_path"
    end
  end
end
