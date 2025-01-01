class AddIndexToPullOrchestrations < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    change_table :pull_request_orchestrations, bulk: true do |t|
      t.index [:pull_request_id, :repository_id, :type, :state], name:  "index_pull_orchestrations_on_pull_id_repository_id_type_state"
      t.index [:state, :updated_at]
      t.index [:updated_at]
    end
  end
end
