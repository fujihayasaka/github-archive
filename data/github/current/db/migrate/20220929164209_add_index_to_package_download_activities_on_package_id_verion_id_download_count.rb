# typed: true

class AddIndexToPackageDownloadActivitiesOnPackageIdVerionIdDownloadCount < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    change_table :package_download_activities, bulk: true do |t|
      t.index [:package_id, :package_version_id, :package_download_count], name: "index_pkg_download_activities_on_pkg_id_ver_id_download_count"
    end
  end
end
