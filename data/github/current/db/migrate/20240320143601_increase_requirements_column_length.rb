class IncreaseRequirementsColumnLength < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Vulnerabilities)

  def up
    change_column :vulnerable_version_ranges, :requirements, "text", null: false
  end

  def down
    change_column :vulnerable_version_ranges, :requirements, "varchar(75)", null: false
  end
end
