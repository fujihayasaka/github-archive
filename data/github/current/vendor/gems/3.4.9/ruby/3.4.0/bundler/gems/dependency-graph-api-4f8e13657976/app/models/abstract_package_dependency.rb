class AbstractPackageDependency < ApplicationRecord
  self.table_name = "dg_abstract_package_dependencies"

  extend AbstractDependencyScoping

  restrict_type_of :package_manager, to: Types::PackageManager

  belongs_to :dependent, class_name: "Package"

  scope :dependent_owned_by, -> (owner) { joins(:dependent).merge(Package.repository_owned_by(owner)) }

  delegate :github_repository_id, :github_owner_id, :name, to: :dependent, allow_nil: true

  def self.recently_added_first
    order(id: :desc)
  end

  # Returns all of the packages mapped to a AbstractPackageDependency collection
  def self.packages
    Package.joins("INNER JOIN #{self.table_name} ON #{Package.table_name}.package_manager = #{self.table_name}.package_manager AND #{Package.table_name}.name = #{self.table_name}.package_name").merge(all)
  end
end
