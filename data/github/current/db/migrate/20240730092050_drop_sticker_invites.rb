class DropStickerInvites < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def up
    drop_table :sticker_invites, if_exists: true
  end

  def down
    # Temporary rubocop ignore, see https://github.com/github/database-reliability/issues/178#issuecomment-2262351456
    create_table :sticker_invites do |t| # rubocop:disable GitHub/UpdateTableOwner
      t.integer :sticker_id, null: false, index: true
      t.integer :number_of_invites, null: false
      t.timestamp :expires_at, precision: 6
      t.boolean :disabled, null: false, default: false
    end
  end
end
