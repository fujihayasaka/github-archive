# typed: true

class AddIndexReleaseMentionsOnReleaseIdAndUserId < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    change_table :release_mentions, bulk: true do |t|
      t.remove_index [:release_id], name: "index_release_mentions_on_release_id"
      t.index [:release_id, :user_id], name: "index_release_mentions_on_release_id_user_id"
    end
  end
end
