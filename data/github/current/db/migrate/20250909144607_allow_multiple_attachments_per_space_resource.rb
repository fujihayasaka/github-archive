# typed: true
# frozen_string_literal: true

class AllowMultipleAttachmentsPerSpaceResource < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :custom_copilot_resources, bulk: true do |t|
      # This is ok because we already have a unique index on copilot_chat_attachment_id, so there are no existing duplicates to worry about.
      # rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn
      t.index [:copilot_chat_attachment_id, :custom_copilot_id], unique: true
      t.remove_index :copilot_chat_attachment_id, unique: true
    end
  end
end
