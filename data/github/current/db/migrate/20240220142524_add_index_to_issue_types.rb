class AddIndexToIssueTypes < ActiveRecord::Migration[7.2]

  self.use_connection_class(ApplicationRecord::IssuesPullRequests)

  def change
    change_table :issue_types, bulk: true do |t|
      t.index [:owner_id], name: "index_issue_types_owner"
    end
  end
end
