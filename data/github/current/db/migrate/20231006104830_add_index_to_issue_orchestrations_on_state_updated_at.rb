class AddIndexToIssueOrchestrationsOnStateUpdatedAt < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    change_table :issue_orchestrations, bulk: true do |t|
      t.index [:state, :updated_at], name: "index_state_updated_at"
      t.index [:updated_at], name: "index_updated_at"
    end
  end
end
