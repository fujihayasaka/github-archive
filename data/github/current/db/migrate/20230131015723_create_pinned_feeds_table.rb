# typed: true

class CreatePinnedFeedsTable < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    create_table :pinned_feeds, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :user_id, unsigned: true, null: false
      t.bigint :topic_id, unsigned: true, null: false

      t.timestamps
    end

    add_index :pinned_feeds, [:user_id, :topic_id], unique: true
  end
end
