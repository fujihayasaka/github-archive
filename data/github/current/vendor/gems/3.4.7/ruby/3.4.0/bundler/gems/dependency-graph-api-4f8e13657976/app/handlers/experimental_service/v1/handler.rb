module ExperimentalService
  module V1
    class Handler < TracedHandler
      def get_releases_for_package(req, env)
        package_manager = Types::PackageManager.from_proto(req.package_manager)
        package_releases = PackageRelease
          .where(package_manager: package_manager, package_name: req.package_name)
          .pluck(:name)
          .map do |name|
            DependencyGraphAPI::V1::GetReleasesForPackageResponse::PackageRelease.new(
              version: name
            )
          end

        DependencyGraphAPI::V1::GetReleasesForPackageResponse.new(
          package_releases: package_releases,
        )
      end
    end
  end
end
