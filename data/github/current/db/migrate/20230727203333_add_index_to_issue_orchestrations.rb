# typed: true

class AddIndexToIssueOrchestrations < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    change_table :issue_orchestrations, bulk: true do |t|
      t.index [:repository_id, :issue_id, :type, :state], name:  "index_issue_orchestrations_on_repository_id_issue_id_type_state"
    end
  end
end
