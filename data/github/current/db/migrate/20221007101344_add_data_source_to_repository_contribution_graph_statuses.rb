# typed: true

# rubocop:disable GitHub/AvoidRedundantIndex
class AddDataSourceToRepositoryContributionGraphStatuses < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Collab)
  def up
    change_table :repository_contribution_graph_statuses, bulk: true do |t|
      t.change :id, :bigint, unsigned: true
      t.change :repository_id, :bigint, unsigned: true
      t.column :data_source, :tinyint, default: 0, null: false
      t.remove_index  name: "index_repository_contribution_graph_statuses_on_repository_id"
      t.index [:repository_id, :data_source], unique: true, name: "index_repository_contribution_graph_statuses_repo_id_data_source"
    end
  end

  def down
    change_table :repository_contribution_graph_statuses, bulk: true do |t|
      t.change :id, :int
      t.change :repository_id, :int
      t.remove :data_source
      t.remove_index  name: "index_repository_contribution_graph_statuses_repo_id_data_source"
      t.index  :repository_id, unique: true, name: "index_repository_contribution_graph_statuses_on_repository_id"
    end
  end
end
