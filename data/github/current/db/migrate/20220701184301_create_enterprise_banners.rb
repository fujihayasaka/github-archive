# typed: true
class CreateEnterpriseBanners < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Collab)

  def up
    create_table :enterprise_banners, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :owner_id, :bigint, unsigned: true, null: false
      t.column :owner_type, :string, null: false, limit: 20
      t.column :message, :string, null: false, limit: 512
      t.column :dismissible, :boolean, null: false, default: false
      t.column :expires_at, :datetime, precision: 6, null: true, index: true

      t.timestamps

      t.index [:owner_id, :owner_type], name: "index_enterprise_banners_on_owner_id_and_owner_type", unique: true
    end
  end

  def down
    drop_table :enterprise_banners, if_exists: true
  end
end
