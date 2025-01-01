# typed: true
# frozen_string_literal: true

class IndexCreatedAtOnCopilotChatAttachments < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    add_index :copilot_chat_attachments, :created_at
  end
end
