module Views
  class AbstractPackageDependencyCount < ApplicationRecord
    self.table_name = "dg_abstract_package_dependency_counts"
    extend AbstractDependencyCount

    restrict_type_of :package_manager, to: Types::PackageManager

    scope :order_by_count, -> { order(dependent_count: :desc) }
    scope :package_manager, -> (package_manager) { where(package_manager: package_manager) }
    scope :package_name, -> (package_name) { where(package_name: package_name) }

    def self.view_manager(insert_into: table_name)
      AbstractDependencyCount::ViewManager.new(
        extract_from: AbstractPackageDependency,
        checkpoint_name: :package_dependent_counts_view,
        insert_into: insert_into,
      )
    end
  end
end
