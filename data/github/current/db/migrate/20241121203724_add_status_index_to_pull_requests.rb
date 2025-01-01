# rubocop:disable GitHub/ArchivedTable
# typed: true

class AddStatusIndexToPullRequests < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    change_table :pull_requests, bulk: true do |t|
      t.index [:repository_id, :user_hidden, :status], name: "index_pull_requests_on_repository_id_user_hidden_and_status"
    end
  end

end

# rubocop:enable GitHub/ArchivedTable
