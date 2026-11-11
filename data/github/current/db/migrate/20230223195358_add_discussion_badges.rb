# typed: true

class AddDiscussionBadges < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Discussions)

  def change
    create_table :discussion_badges, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :user_id, unsigned: true, null: false
      t.bigint :repository_id, unsigned: true, null: false

      t.datetime :invited_at, null: false, precision: 6
      t.datetime :accepted_at, null: false, precision: 6
      t.datetime :revoked_at, null: false, precision: 6
      t.datetime :rejected_at, null: false, precision: 6

      t.timestamps null: false
    end
  end
end
