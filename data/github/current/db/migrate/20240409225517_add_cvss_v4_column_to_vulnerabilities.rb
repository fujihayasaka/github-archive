class AddCvssV4ColumnToVulnerabilities < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Vulnerabilities)

  def change
    change_table :vulnerabilities, bulk: true do |t|
      t.column :cvss_v4, "varchar(255)", null: true
    end
  end
end
