# typed: true

class AddImposerRepositoryIdColumnToWorkflows < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::RepositoriesActionsChecks)

  def up
    change_table :workflows, bulk: true do |t|
      t.column :imposer_repository_id, :bigint, unsigned: true, null: false, default: 0, comment: "Id of the repository where the required workflow file resides"
      t.index [:repository_id, :path, :imposer_repository_id], unique: true, name: "index_workflows_on_repository_id_path_and_imposer_repository_id"
    end
  end

  def down
    change_table :workflows, bulk: true do |t|
      t.remove :imposer_repository_id
      t.remove_index [:repository_id, :path, :imposer_repository_id], name: "index_workflows_on_repository_id_path_and_imposer_repository_id"
    end
  end
end
