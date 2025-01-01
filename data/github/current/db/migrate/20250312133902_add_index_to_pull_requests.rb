# typed: true

# rubocop:disable GitHub/AvoidRedundantIndex
# rubocop:disable GitHub/ArchivedTable#GitHub/ArchivedTable

class AddIndexToPullRequests < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    change_table :pull_requests, bulk: true do |t|
      t.index [:repository_id, :created_at, :user_hidden, :user_id], name:  "index_prs_on_repository_id_created_at_user_hidden_user_id"
    end
  end
end
