# typed: true
# frozen_string_literal: true

class Registry::Dependency < ApplicationRecord::Domain::Repositories # rubocop:todo GitHub/DatabaseModelsShouldHaveTests
  self.table_name = :registry_package_dependencies

  include GitHub::Relay::GlobalIdentification

  # rubocop:todo Rails/InverseOf
  belongs_to :package_version, class_name: "Registry::PackageVersion", foreign_key: "registry_package_version_id"
  # rubocop:enable Rails/InverseOf

  enum :dependency_type, {
    default: 0,
    dev: 1,
    test: 2,
    peer: 3,
    optional: 4,
    bundled: 5,
    predepends: 6,
    recommends: 7,
    suggests: 8,
    enhances: 9,
    breaks: 10,
    conflicts: 11,
    replaces: 12,
    provides: 13,
  }

  def platform_type_name
    "PackageDependency"
  end
end
