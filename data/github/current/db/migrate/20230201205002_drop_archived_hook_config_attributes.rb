# typed: true
# frozen_string_literal: true

class DropArchivedHookConfigAttributes < ActiveRecord::Migration[7.1]
  def change
    drop_table :archived_hook_config_attributes, if_exists: true
  end
end
