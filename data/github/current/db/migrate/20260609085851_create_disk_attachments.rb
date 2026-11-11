# typed: true
# frozen_string_literal: true

class CreateDiskAttachments < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Spokes)

  def up
    create_table :disk_attachments, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :fileserver_id, null: false, unsigned: true
      t.string :disk_id, limit: 255, null: false
      t.column :disk_type, "enum('UltraSSD_LRS', 'Premium_LRS', 'PremiumV2_LRS', 'Standard_LRS', 'StandardSSD_LRS')", null: true
      t.column :attachment_mode, "enum('read-write', 'read-only')", null: false, default: "read-write"
      t.datetime :attached_at, null: false, precision: nil
      t.datetime :detached_at, null: true, precision: nil

      t.index [:fileserver_id, :disk_id], unique: true, name: "index_disk_attachments_on_fileserver_id_and_disk_id"
      t.index :disk_id, name: "index_disk_attachments_on_disk_id"
    end
  end

  def down
    if table_exists?(:disk_attachments)
      drop_table :disk_attachments
    end
  end
end
