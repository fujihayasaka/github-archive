class RemoveLastDownloadedAtFromGhesLicenses < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::LicensingCollab)

  def change
    remove_column :ghes_licenses, :last_downloaded_at, :datetime
  end
end
