# typed: true
class AddMigrationStageToProtectedBranch < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    change_table :protected_branches, bulk: true do |t|
      t.column :migration_stage, :integer, null: false, default: 0
    end
  end
end
