# typed: true
# frozen_string_literal: true

class AddIndexOnThreadIdToCopilotChatAttachments < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    change_table :copilot_chat_attachments, bulk: true do |t|
      t.index [:thread_id], name: "index_copilot_chat_attachments_on_thread_id"
    end
  end
end
