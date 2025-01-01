# typed: true

class AddDismissViaCopilotQuotaToReviewRequest < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def up
    change_table :review_requests, bulk: true do |t|
      t.boolean :dismissed_via_copilot_quota, null: true, default: false
    end

    change_table :archived_review_requests, bulk: true do |t|
      t.boolean :dismissed_via_copilot_quota, null: true, default: false
    end
  end

  def down
    change_table :review_requests, bulk: true do |t|
      t.remove :dismissed_via_copilot_quota
    end

    change_table :archived_review_requests, bulk: true do |t|
      t.remove :dismissed_via_copilot_quota
    end
  end
end
