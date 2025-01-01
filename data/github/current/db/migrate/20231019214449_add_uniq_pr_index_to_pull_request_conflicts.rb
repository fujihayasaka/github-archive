# rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn

class AddUniqPrIndexToPullRequestConflicts < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    change_table :pull_request_conflicts, bulk: true do |t|
      t.index [:pull_request_id, :conflict_type], name:  "index_pull_conflicts_on_pull_id_and_type", unique: true
    end
  end
end
