# typed: true
# frozen_string_literal: true

class SecurityCenterDropRepoLastPush < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    change_table :repository_security_center_configs, bulk: true do |t|
      t.remove_index name: "index_repo_and_last_push"
      t.remove_index name: "index_repo_security_center_configs_owner_id_last_push_repo_id"
      t.remove :last_push
    end
  end
end
