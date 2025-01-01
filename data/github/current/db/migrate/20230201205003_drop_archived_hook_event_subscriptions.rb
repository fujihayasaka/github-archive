# typed: true
# frozen_string_literal: true

class DropArchivedHookEventSubscriptions < ActiveRecord::Migration[7.1]
  def change
    drop_table :archived_hook_event_subscriptions, if_exists: true
  end
end
