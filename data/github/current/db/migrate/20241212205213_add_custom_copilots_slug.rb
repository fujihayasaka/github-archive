# typed: true

class AddCustomCopilotsSlug < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def up
    change_table :custom_copilots, bulk: true do |t|
      t.column :slug, :string, null: false, limit: 255
      t.index [:owner_id, :owner_type, :slug], unique: true
    end
  end

  def down
    change_table :custom_copilots, bulk: true do |t|
      t.remove :slug
      t.remove_index [:owner_id, :owner_type, :slug], name: "index_custom_copilots_on_owner_id_and_owner_type_and_slug"
    end
  end
end
