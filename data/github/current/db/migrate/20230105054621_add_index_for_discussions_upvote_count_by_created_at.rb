# typed: true
class AddIndexForDiscussionsUpvoteCountByCreatedAt < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Discussions)

  def change
    change_table :discussions, bulk: true do |t|
      t.index [:repository_id, :created_at, :total_upvotes], name: "index_repo_upvotes_created_at"
    end
  end
end
