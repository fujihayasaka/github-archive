class AddIndexToRepositoryIssueTypes < ActiveRecord::Migration[7.2]

  self.use_connection_class(ApplicationRecord::IssuesPullRequests)

  def change
    change_table :repository_issue_types, bulk: true do |t|
      t.index [:repository_id, :issue_type_id], name: "index_repository_issue_types_on_repository_id_and_issue_type_id"
    end
  end
end
