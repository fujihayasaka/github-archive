# typed: true

class AddInteractionLimitIndex < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesCollab)

  def change
    add_index :interaction_limits, [:repository_id, :target, :expires_at], name: "idx_interaction_limits_on_repo_id_target_expires_at"
  end
end
