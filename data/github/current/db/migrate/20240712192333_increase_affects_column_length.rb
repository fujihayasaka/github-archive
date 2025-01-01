class IncreaseAffectsColumnLength < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Vulnerabilities)

  def up
    change_column :vulnerable_version_ranges, :affects, "varchar(255)", null: false
  end

  def down
    change_column :vulnerable_version_ranges, :affects, "varchar(100)", null: false
  end
end
