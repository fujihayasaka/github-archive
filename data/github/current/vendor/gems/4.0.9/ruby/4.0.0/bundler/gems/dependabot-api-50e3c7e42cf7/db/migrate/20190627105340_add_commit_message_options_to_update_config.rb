# frozen_string_literal: true

class AddCommitMessageOptionsToUpdateConfig < ActiveRecord::Migration[6.0]
  def change
    change_table :update_configs, bulk: true do |t| # rubocop:disable Rails/NoBulkChangeTable
      t.string :commit_message_prefix, limit: 15
      t.boolean :commit_message_include_scope
    end
  end
end
