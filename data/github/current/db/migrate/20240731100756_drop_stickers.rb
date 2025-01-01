class DropStickers < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def up
    drop_table :stickers, if_exists: true
  end

  def down
    # Temporary rubocop ignore, see https://github.com/github/database-reliability/issues/178#issuecomment-2262351456
    create_table :stickers do |t| # rubocop:disable GitHub/UpdateTableOwner
      t.string :reference_type
      t.integer :reference_id
      t.text :url
      t.text :alt
      t.text :permalink
      t.boolean :published, default: false, null: false
      t.timestamps
      t.index [:reference_type, :reference_id], name: "index_stickers_on_reference"
    end
  end
end
