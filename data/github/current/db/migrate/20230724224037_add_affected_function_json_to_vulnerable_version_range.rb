# typed: true

class AddAffectedFunctionJsonToVulnerableVersionRange < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Vulnerabilities)

  def change
    add_column :vulnerable_version_ranges, :affected_functions_json, :json, null: true
  end
end
