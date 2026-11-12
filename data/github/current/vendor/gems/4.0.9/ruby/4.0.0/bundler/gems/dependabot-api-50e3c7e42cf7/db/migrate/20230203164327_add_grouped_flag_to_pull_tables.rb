# frozen_string_literal: true

class AddGroupedFlagToPullTables < ActiveRecord::Migration[7.0]
  def change
    add_column :pull_requests, :grouped_update, :boolean, default: false
    add_column :pending_pull_requests, :grouped_update, :boolean, default: false
  end
end
