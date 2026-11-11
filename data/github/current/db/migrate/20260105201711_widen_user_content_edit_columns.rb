# typed: true
# frozen_string_literal: true

class WidenUserContentEditColumns < ActiveRecord::Migration[8.2]
  use_connection_class(ApplicationRecord::Domain::UserContentEdits)

  def up
    change_table :user_content_edits, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false
      t.change :user_content_id, :bigint, unsigned: true, null: false
      t.change :editor_id, :bigint, unsigned: true, null: false
      t.change :performed_by_integration_id, :bigint, unsigned: true
      t.change :deleted_by_id, :bigint, unsigned: true
    end
  end

  def down
    change_table :user_content_edits, bulk: true do |t|
      t.change :id, :int, null: false
      t.change :user_content_id, :int, null: false
      t.change :editor_id, :int, null: false
      t.change :performed_by_integration_id, :int
      t.change :deleted_by_id, :int
    end
  end
end
