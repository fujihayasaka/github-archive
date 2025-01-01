# rubocop:disable GitHub/ArchivedTable
# typed: true

# rubocop:disable GitHub/AvoidRedundantIndex

class AddRepoUserStatusIndexToPullRequests < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    change_table :pull_requests, bulk: true do |t|
      t.index [:repository_id, :status, :user_id, :user_hidden], name: "index_prs_on_repository_id_status_user_id_user_hidden"

      t.remove_index [:repository_id, :user_id, :user_hidden], name: "index_pull_requests_on_repository_id_and_user_id_and_user_hidden"
    end
  end
end

# rubocop:enable GitHub/ArchivedTable
