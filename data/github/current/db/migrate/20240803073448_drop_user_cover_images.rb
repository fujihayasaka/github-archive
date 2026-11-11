class DropUserCoverImages < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def up
    drop_table :user_cover_images, if_exists: true
  end

  def down
    create_table :user_cover_images do |t|
      t.integer :user_id, null: false
      t.text :url
      t.text :alt
      t.string :background_color, limit: 6
      t.text :metadata
      t.timestamps precision: 6
    end
  end
end
