module PackageManagerScoping
  def for_package_manager(package_managers)
    package_managers = Array.wrap(package_managers).map do |package_manager|
      Types::PackageManager.coerce(package_manager)
    end

    where(package_manager: package_managers)
  end
end
