# typed: true

class AddVerifiedAtToDiscussions < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Discussions)

  def change
    change_table :discussions, bulk: true do |t|
      t.datetime :verified_at, after: :chosen_comment_id, precision: 6
    end
  end
end
