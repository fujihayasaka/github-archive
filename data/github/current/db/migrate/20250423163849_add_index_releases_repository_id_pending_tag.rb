# typed: true

class AddIndexReleasesRepositoryIdPendingTag < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    add_index :releases, [:repository_id, :pending_tag], length: { pending_tag: 50 }, name: "by_repo_and_pending_tag"
  end
end
