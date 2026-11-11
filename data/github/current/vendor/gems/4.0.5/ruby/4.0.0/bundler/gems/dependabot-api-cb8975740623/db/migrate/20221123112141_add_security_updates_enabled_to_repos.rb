# frozen_string_literal: true

class AddSecurityUpdatesEnabledToRepos < ActiveRecord::Migration[7.0]
  def change
    add_column :repos, :security_updates_enabled, :boolean
  end
end
