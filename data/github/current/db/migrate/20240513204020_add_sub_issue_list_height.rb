class AddSubIssueListHeight < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)
  def change
    change_table :sub_issue_lists, bulk: true do |t|
      t.column :height, :tinyint, unsigned: true, default: 0, null: false
    end
  end
end
