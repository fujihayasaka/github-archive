# typed: true
# frozen_string_literal: true

class Registry::Tag < ApplicationRecord::Domain::Packages # rubocop:todo GitHub/DatabaseModelsShouldHaveTests
  self.table_name = :registry_package_tags

  include GitHub::Relay::GlobalIdentification

  # rubocop:todo Rails/InverseOf
  belongs_to :package, class_name: "Registry::Package", foreign_key: :registry_package_id
  belongs_to :package_version, class_name: "Registry::PackageVersion", foreign_key: :registry_package_version_id
  # rubocop:enable Rails/InverseOf

  validates :name, presence: true, uniqueness: { scope: :registry_package_id, case_sensitive: false }

  def platform_type_name
    "PackageTag"
  end
end
