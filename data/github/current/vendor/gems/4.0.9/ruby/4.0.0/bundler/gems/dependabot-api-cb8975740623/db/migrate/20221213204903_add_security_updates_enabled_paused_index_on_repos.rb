# frozen_string_literal: true

class AddSecurityUpdatesEnabledPausedIndexOnRepos < ActiveRecord::Migration[7.0]
  def change
    remove_index :repos, :paused_at
    add_index :repos, %i(paused_at security_updates_enabled will_pause_at), name: "index_repos_on_security_updates_enabled_and_paused"
  end
end
