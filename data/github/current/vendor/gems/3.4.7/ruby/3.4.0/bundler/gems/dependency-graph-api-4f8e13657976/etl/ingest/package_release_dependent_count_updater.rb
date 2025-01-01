module Ingest
  class PackageReleaseDependentCountUpdater
    class << self
      def run!(**kwargs)
        GitHub::Telemetry.tracer.in_span("PackageReleaseDependentCountUpdater") do
          new(**kwargs).run
        end
      end
    end

    attr_accessor :github_owner_id, :dependencies_in_last_revision, :dependencies_in_this_revision

    def initialize(github_owner_id:, dependencies_in_last_revision:, dependencies_in_this_revision:)
      @github_owner_id = github_owner_id
      @dependencies_in_last_revision = to_dependency_set(dependencies_in_last_revision)
      @dependencies_in_this_revision = to_dependency_set(dependencies_in_this_revision)
    end

    def run
      package_releases_added = get_package_release_ids(dependencies_added)
      package_releases_removed = get_package_release_ids(dependencies_removed)

      records = package_releases_added.map do |package_release_id|
        Views::PackageReleaseDependentCount.new(
          github_owner_id: github_owner_id,
          package_release_id: package_release_id,
          count: 1
        )
      end

      records.each_slice(10) do |slice|
        Views::PackageReleaseDependentCount.import(slice,
          on_duplicate_key_update: "count = count + 1"
        )
      end

      package_releases_removed.each_slice(10) do |slice|
        Views::PackageReleaseDependentCount
          .where(github_owner_id: github_owner_id, package_release_id: slice)
          .update_counters(count: -1)
      end

      package_releases_removed.each_slice(10) do |slice|
        Views::PackageReleaseDependentCount
          .where(github_owner_id: github_owner_id, package_release_id: slice)
          .where("count <= 0")
          .delete_all
      end
    end

    private

    def to_dependency_set(deps)
      deps
        .filter_map do |dep|
          if dep.requirement_set.exact_version.present?
            { package_manager: dep.package_manager.to_i,
              package_name: dep.package_name,
              exact_version: normalized_exact_version(dependency: dep) }
          end
        end
        .to_set
    end

    def dependencies_added
      dependencies_in_this_revision - dependencies_in_last_revision
    end

    def dependencies_removed
      dependencies_in_last_revision - dependencies_in_this_revision
    end

    def get_package_release_ids(dependencies)
      ActiveRecord::Base.connected_to(role: :reading) do
        dependencies.each_slice(1000).flat_map do |batch|
          PackageRelease
            .where([:package_manager, :package_name, :name] => batch.pluck(:package_manager, :package_name, :exact_version))
            .pluck(:id)
        end
      end
    end

    def normalized_exact_version(dependency:)
      if dependency.package_manager == Types::PackageManager[:go]
        return "v#{dependency.requirement_set.exact_version}"
      end
      dependency.requirement_set.exact_version
    end
  end
end
