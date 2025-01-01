# typed: true
class UpdateDiscussionEventsIds < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Discussions)

  def change
    change_table :discussion_events, bulk: true do |t|
      t.change :id, :bigint, unsigned: true
      t.change :repository_id, :bigint, unsigned: true
      t.change :discussion_id, :bigint, unsigned: true
      t.change :actor_id, :bigint, unsigned: true
      t.change :comment_id, :bigint, unsigned: true
    end
  end
end
