# typed: true

class AddPostAsAdminToDiscussionComment < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Discussions)

  def change
    change_table :discussion_comments, bulk: true do |t|
      t.boolean :post_as_admin, default: false, null: false, index: true
    end
  end
end
