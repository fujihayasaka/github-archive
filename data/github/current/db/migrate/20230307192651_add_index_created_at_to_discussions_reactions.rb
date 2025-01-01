# typed: true

class AddIndexCreatedAtToDiscussionsReactions < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Discussions)

  def change
    change_table :discussion_reactions, bulk: true do |t|
      t.change :id, :bigint, unsigned: true
      t.change :discussion_id, :bigint, unsigned: true
      t.change :user_id, :bigint, unsigned: true
    end

    add_index :discussion_reactions, :created_at
  end
end
