class Attribution < ApplicationRecord
  self.table_name = "dg_attributions"

  belongs_to :package_release,
    class_name:  "PackageRelease",
    foreign_key: :dg_package_versions_id

end
