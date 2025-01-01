# typed: false
class AddHcsChangelogVersionToSecretScanningScans < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def up
    add_column :secret_scanning_scans, :hcs_changelog_version, :string, limit: 255, null: true, comment: "The HCS changelog version that was used to run this scan"
  end

  def down
    drop_column :secret_scanning_scans, :hcs_changelog_version
  end
end
