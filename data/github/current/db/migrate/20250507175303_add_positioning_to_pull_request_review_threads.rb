# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/ArchivedTable#GitHub/ArchivedTable

class AddPositioningToPullRequestReviewThreads < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    change_table :pull_request_review_threads, bulk: true do |t|
      t.json :original_positioning, null: true
      t.json :latest_positioning, null: true
    end
  end
end
