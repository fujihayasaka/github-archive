# typed: true
class AddUniqueConstraintsToIssues < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::IssuesPullRequests)

  def up
    change_table :issues, bulk: true do |t|
      t.index [:pull_request_id], unique: true, name: "index_issues_on_pull_request_id_unique"

      t.remove_index name: "index_issues_on_pull_request_id"
    end
  end

  def down
    change_table :issues, bulk: true do |t|
      t.remove_index name: "index_issues_on_pull_request_id_unique"

      t.index [:pull_request_id], name: "index_issues_on_pull_request_id"
    end
  end
end
