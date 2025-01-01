class AddRunnerGroupAndLabelToPrebuilds < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Codespaces)

  def change
    change_table :codespace_prebuild_configurations, bulk: true do |t|
      t.string :runner_group, limit: 128
      t.string :runner_label, limit: 64
    end
  end
end
