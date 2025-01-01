# typed: true

class AddUserAutomaticCodeReviewToCopilotPolicies < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)
  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :user_automatic_code_review, :integer, limit: 1, null: false, default: 0, comment: "Automatically request Copilot code reviews for a user"
    end
  end
end
