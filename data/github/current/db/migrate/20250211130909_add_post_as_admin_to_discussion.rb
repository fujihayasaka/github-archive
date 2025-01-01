# typed: true

class AddPostAsAdminToDiscussion < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Discussions)

  def change
    change_table :discussions, bulk: true do |t|
      t.boolean :post_as_admin, default: false, null: false, index: true
    end
  end
end
