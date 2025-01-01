# typed: true
class MakeFixedAlertmessageNonNil < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::IssuesPullRequests)

  def change
    change_table(:code_scanning_review_comments, bulk: true) do |t|
      t.change :alert_message, :blob, null: false
      t.change :fixed, :boolean, after: :alert_number, default: false, null: false
    end
  end
end
