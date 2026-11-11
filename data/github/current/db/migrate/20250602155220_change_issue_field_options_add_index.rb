# typed: true

class ChangeIssueFieldOptionsAddIndex < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    change_table :issue_field_options, bulk: true do |t|
      # Efficiently retrieves issue field options by issue field ID and name
      t.index [:issue_field_id, :name], name: "index_issue_field_options_on_issue_field_id_name"
    end
  end
end
