# typed: true

class AddCodeScanningOptionToSecurityConfigs < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    change_table(:security_configurations, bulk: true) do |t|
      # Add nullable json column for Code Scanning options values.
      t.column :code_scanning_options, :json, null: true
    end
  end
end
