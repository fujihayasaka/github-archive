class DropUserStickers < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def up
    drop_table :user_stickers, if_exists: true
  end

  def down
    create_table :user_stickers do |t|
      t.integer :user_id, null: false, index: true
      t.integer :sticker_id, null: false, index: true
      t.integer :sticker_invite_id, index: true
      t.index [:user_id, :sticker_id], unique: true, name: "index_user_stickers_on_user_id_and_sticker_id"
    end
  end
end
