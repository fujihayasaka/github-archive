class AddSeverityToVulnerableVersionRange < ActiveRecord::Migration[5.2]
  def change
    add_column :dg_vulnerable_version_ranges, :severity, :string, limit: 12
  end
end
