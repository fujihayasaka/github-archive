# typed: true

class DropDiscussionBadges < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Discussions)

  def up
    drop_table :discussion_badges
  end

  def down
    create_table :discussion_badges, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :user_id, unsigned: true, null: false
      t.bigint :repository_id, unsigned: true, null: false

      t.datetime :accepted_at, null: true, precision: 6
      t.datetime :revoked_at, null: true, precision: 6
      t.datetime :rejected_at, null: true, precision: 6

      t.timestamps null: false

      t.bigint :sender_id, unsigned: true, null: false
    end
  end
end
