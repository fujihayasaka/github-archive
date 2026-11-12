# typed: true
# frozen_string_literal: true

require "github/transitions/20260105201710_fix_zero_dates_in_user_content_edits"

class WidenUserContentEditColumns < ActiveRecord::Migration[8.2]
  use_connection_class(ApplicationRecord::Domain::UserContentEdits)

  def up
    if GitHub.enterprise? || Rails.env.development?
      arguments = GitHub::Transitions::Arguments.new(dry_run: false)
      transition = GitHub::Transitions::FixZeroDatesInUserContentEdits.new(arguments)
      transition.run
    end

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
