# typed: true
class ChangeCodespacesPrebuildConfigurationIndex < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Codespaces)

  def change
    change_table :codespace_prebuild_configurations, bulk: true do |t|
      t.index [:repository_id, :branch, :vscs_target, :devcontainer_path], name: "codespace_prebuild_config_repo_branch_target_devcontainer", unique: true
      t.remove_index [:branch, :repository_id, :vscs_target, :devcontainer_path], name: "codespace_prebuild_config_branch_repo_target_devcontainer", unique: true
    end
  end
end
