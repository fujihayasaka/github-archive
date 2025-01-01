# typed: true

class ChangeIssueFieldValuesAddIndex < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    change_table :issue_field_values, bulk: true do |t|
      # Efficiently retrieves the value of a specific issue field for an issue
      t.index [:issue_id, :issue_field_id, :data_type], name: "index_issue_field_values_on_issue_id_issue_field_id_data_type"

      # Efficiently delete multiple issue field value when an issue field option is deleted
      t.index [:issue_field_id, :data_type], name: "index_issue_field_values_on_issue_field_id_data_type"
    end
  end
end
