# typed: true
class RenamePackageListedColumnInRepositoryActions < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def up
    change_table :repository_actions, bulk: true do |t|
      t.column :action_package_listed, "tinyint(1)", null: false, default: 0
      t.remove :package_listed
    end
  end

  def down
    change_table :repository_actions, bulk: true do |t|
      t.column :package_listed, "tinyint(1)", null: false, default: 0
      t.remove :action_package_listed
    end
  end
end
