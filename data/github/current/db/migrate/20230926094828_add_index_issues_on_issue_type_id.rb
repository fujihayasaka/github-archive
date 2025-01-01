class AddIndexIssuesOnIssueTypeId < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def up
    change_table :issues, bulk: true do |t|
      t.index [:issue_type_id], name: "index_issues_on_issue_type_id"
    end
  end

  def down
    change_table :issues, bulk: true do |t|
      t.remove_index name: "index_issues_on_issue_type_id"
    end
  end
end
