class PackageDependency < ApplicationRecord
  self.table_name = "dg_dependency_specifications"

  include Dependency

  # The package version that has specified the dependency.
  #
  # returns a PackageRelease
  belongs_to :dependent,
    class_name:  "PackageRelease",
    foreign_key: :dependent_id,
    required:    false

  restrict_type_of :package_manager, to: Types::PackageManager

  validates :requirements, length: { maximum: 255 }

  def package_label
    self[:package_label].presence || package_name
  end
end
