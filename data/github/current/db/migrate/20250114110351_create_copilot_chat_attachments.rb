# typed: true
# frozen_string_literal: true

class CreateCopilotChatAttachments < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    create_table :copilot_chat_attachments, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :name, null: false
      t.string :guid, limit: 36, null: false
      t.bigint :uploader_id, unsigned: true, null: false
      t.bigint :storage_blob_id, unsigned: true
      t.integer :state, default: 0, null: false
      t.integer :size, null: false
      t.string :content_type, null: false

      t.timestamps

      t.index [:uploader_id, :state]
    end
  end
end
