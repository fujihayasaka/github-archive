module PackagesService
  module V1
    class Handler
      include DependencyGraph::Tracing

      MAX_PACKAGES = 500

      trace_method :get_package_versions
      def get_package_versions(req, env)
        if req.package_versions.length > MAX_PACKAGES || req.package_versions.empty?
          raise "Request must contain between 1 and #{MAX_PACKAGES} package versions"
        end

        package_versions = req.package_versions.map do |spec|
          [
            spec.package_name,
            Types::PackageManager.from_proto(spec.package_manager),
            spec.package_version
          ]
        end

        package_releases = PackageRelease
          .where([:package_name, :package_manager, :name] => package_versions)

        attributions = {}
        if req.include_copyright_attributions
          release_ids = package_releases.map(&:id)
          attributions = get_attributions(release_ids)
        end

        response_pvs = package_releases.map do |release|
          DependencyGraphAPI::V1::GetPackageVersionsResponse::PackageVersion.new(
            package_manager: release.package_manager.to_proto,
            package_name: release.package_name,
            name: release.name,
            license: release.license,
            attributions: attributions[release.id],
            source_url: release.source_url,
            published_at: release.published_at&.to_time,
            unpublished_at: release.unpublished_at&.to_time,
          )
        end

        DependencyGraphAPI::V1::GetPackageVersionsResponse.new(
          package_versions: response_pvs,
        )
      end

      trace_method :list_package_versions, span_attribute_extractor: -> (_instance, *args, **_kwargs) do
        {
          "gh.dependency_graph.package_manager" => args[0].package_manager.to_s,
          "gh.dependency_graph.package_name"    => args[0].package_name,
        }
      end
      def list_package_versions(req, env)
        if req.package_manager.blank? || req.package_name.blank?
          raise "Request must contain both package manager and package name"
        end

        package_manager = Types::PackageManager.from_proto(req.package_manager)
        package_name = req.package_name

        fields = [:name]
        if req.include_licenses
          fields << [:license]
        end

        releases = PackageRelease
          .where(package_manager: package_manager, package_name: package_name)
          .pluck(*fields)

        response_pvs = releases.map do |release|
          package_version, package_license = release
          DependencyGraphAPI::V1::ListPackageVersionsResponse::PackageVersion.new(
            package_version: package_version,
            package_license: package_license
          )
        end

        DependencyGraphAPI::V1::ListPackageVersionsResponse.new(
          package_versions: response_pvs,
        )
      end

      private

      trace_method :get_attributions
      def get_attributions(package_release_ids)
        # create a table of `key => license` rows. `key` is a unique
        # release identifier.
        attributions = {}

        Attribution
          .where(dg_package_versions_id: package_release_ids)
          .pluck(:dg_package_versions_id, :attribution)
          .each do |package_release_id, attribution|
            attributions[package_release_id] ||= []
            attributions[package_release_id] << attribution
          end

        attributions
      end
    end
  end
end
