class AddIssueTypeIdToIssues < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def up
    change_table :issues, bulk: true do |t|
      t.bigint :issue_type_id, unsigned: true, null: true
    end
  end

  def down
    change_table :issues, bulk: true do |t|
      t.remove :issue_type_id
    end
  end
end
