# typed: true
# frozen_string_literal: true

class AddThreadIdToCopilotChatAttachments < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    change_table :copilot_chat_attachments, bulk: true do |t|
      t.string :thread_id, null: true, limit: 36, comment: "Thread ID, if the chat attachment is associated to a chat thread."
    end
  end
end
