class AddFailureReasonToRepositorySecurityConfigurations < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    change_table :repository_security_configurations, bulk: true do |t|
      t.column :failure_reason, :text, null: true
    end
  end
end
