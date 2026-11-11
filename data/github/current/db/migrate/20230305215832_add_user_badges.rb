# typed: true

class AddUserBadges < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Badges)

  def change
    create_table :badges, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :user_id, unsigned: true, null: false
      t.bigint :repository_id, unsigned: true, null: false

      t.boolean :contributor, null: false, default: false
      t.boolean :collaborator, null: false, default: false
      t.boolean :first_time_contributor, null: false, default: false
      t.boolean :first_timer, null: false, default: false
      t.boolean :maintainer, null: false, default: false
      t.boolean :member, null: false, default: false
      t.boolean :owner, null: false, default: false
      t.boolean :spammy, null: false, default: false
      t.boolean :sponsor, null: false, default: false

      t.timestamps null: false

      t.index [:user_id, :repository_id], unique: true
      t.index :repository_id
    end
  end
end
