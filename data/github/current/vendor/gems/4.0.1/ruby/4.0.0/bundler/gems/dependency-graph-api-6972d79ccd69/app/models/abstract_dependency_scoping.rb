module AbstractDependencyScoping
  include PackageManagerScoping

  # Public: Query for all packages with specified name.
  def with_package_name(package_name)
    where(package_name: package_name)
  end

  # Public: Query for all abstract dependencies for a given package.
  def depends_on(package)
    for_package_manager(package.package_manager)
      .with_package_name(package.name)
  end
end
