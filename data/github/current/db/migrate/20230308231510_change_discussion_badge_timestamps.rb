# typed: true

class ChangeDiscussionBadgeTimestamps < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Discussions)

  def up
    change_table :discussion_badges, bulk: true do |t|
      t.change :accepted_at, :datetime, null: true
      t.change :revoked_at, :datetime, null: true
      t.change :rejected_at, :datetime, null: true

      t.remove :invited_at

      t.bigint :sender_id, unsigned: true, null: false
    end
  end

  def down
    change_table :discussion_badges, bulk: true do |t|
      t.change :accepted_at, :datetime, null: false
      t.change :revoked_at, :datetime, null: false
      t.change :rejected_at, :datetime, null: false

      t.datetime :invited_at, null: false, precision: 6

      t.remove :sender_id
    end
  end
end
