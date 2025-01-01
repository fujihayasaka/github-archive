# typed: true
class AddVirtualRepositoryIdColumnToMemexActions < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Memexes)

  def change
    change_table :memex_project_workflow_actions, bulk: true do |t|
      t.virtual :repository_id, type: :bigint, as: "(`arguments` ->> '$.repositoryId')"

      t.index [:repository_id, :action_type, :memex_project_workflow_id],
        name: "index_mpwa_on_repo_id_mpwa_type_and_mpw_id"
    end
  end
end
