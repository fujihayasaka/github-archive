# typed: true
# frozen_string_literal: true

# rubocop:todo GitHub/DatabaseModelsShouldHaveTests
class Registry::ManifestEntry < ApplicationRecord::Domain::Packages
  # rubocop:enable GitHub/DatabaseModelsShouldHaveTests
  self.table_name = :package_version_package_files

  include GitHub::Relay::GlobalIdentification
  belongs_to :package_version, class_name: "Registry::PackageVersion"
  belongs_to :file, class_name: "Registry::File", foreign_key: :package_file_id # rubocop:todo Rails/InverseOf

  def platform_type_name
    "PackageVersionPackageFile"
  end
end
