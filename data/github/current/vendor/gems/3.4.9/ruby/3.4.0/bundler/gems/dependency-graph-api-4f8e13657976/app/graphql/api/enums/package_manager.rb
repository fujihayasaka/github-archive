module API
  module Enums
    class PackageManager < Types::BaseEnum
      description "Package managers"

      ::Types::PackageManager.each do |package_manager|
        value(package_manager.name.upcase.to_s, "#{package_manager.human_name} package manager", value: package_manager)
      end
    end
  end
end
