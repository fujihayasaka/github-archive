# frozen_string_literal: true

class UpdateCommitPrefixColumns < ActiveRecord::Migration[7.0]
  def up
    change_column :update_configs, :commit_message_prefix, :string, limit: 50
    change_column :update_configs, :commit_message_prefix_development, :string, limit: 50
  end

  def down
    change_column :update_configs, :commit_message_prefix_development, :string, limit: 15
    change_column :update_configs, :commit_message_prefix_development, :string, limit: 15
  end
end
