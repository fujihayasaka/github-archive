class UniqueVulnerabilities < ActiveRecord::Migration[5.0]
  def change
    add_index :vulnerable_version_ranges, :github_id, unique: true
  end
end
