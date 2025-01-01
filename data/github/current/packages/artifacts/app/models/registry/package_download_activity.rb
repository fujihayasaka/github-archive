# typed: true
# frozen_string_literal: true

class Registry::PackageDownloadActivity < ApplicationRecord::Domain::Repositories
  self.table_name = :package_download_activities

  include GitHub::Relay::GlobalIdentification

  belongs_to :package_version, class_name: "Registry::PackageVersion"
  belongs_to :package, class_name: "Registry::Package"

  def self.track(package_id, package_version_id, started_at)
    sql_bindings = {
      package_id: package_id,
      package_version_id: package_version_id,
      started_at: started_at.utc,
      package_download_count: 1,
    }

    q = <<-SQL
      INSERT INTO package_download_activities (
        package_id,
        package_version_id,
        started_at,
        package_download_count
      ) VALUES (
        :package_id,
        :package_version_id,
        :started_at,
        :package_download_count
      ) ON DUPLICATE KEY UPDATE
        package_download_count = package_download_count+VALUES(package_download_count)
    SQL

    ActiveRecord::Base.connected_to(role: :writing) do
      self.connection.insert(Arel.sql(q, **sql_bindings))
    end

    Search.add_to_search_index("registry_package", package_id, interval: 60)
  end

end
