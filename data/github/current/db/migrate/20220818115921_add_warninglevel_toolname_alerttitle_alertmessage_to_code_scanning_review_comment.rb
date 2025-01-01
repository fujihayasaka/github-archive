# typed: true
class AddWarninglevelToolnameAlerttitleAlertmessageToCodeScanningReviewComment < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::IssuesPullRequests)

  def change
    change_table :code_scanning_review_comments, bulk: true do |t|
      t.string :warning_level, default: nil
      t.string :tool_name, default: nil
      t.column :alert_title, "varbinary(1024)", default: nil
      t.blob :alert_message, default: nil
    end
  end
end
