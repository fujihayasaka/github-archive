# Public: Accepts raw manifest content and metadata and returns parsed data.
class ParsedManifest
  attr_reader :github_repository_id, :filename, :path

  def initialize(github_repository_id:, filename:, path:, content:)
    @github_repository_id = github_repository_id
    @filename             = filename
    @path                 = path
    @content              = content
    @recognized           = ::ManifestAdapters.parse(
      filename: filename,
      path:     path,
      content:  content,
      git_ref: "0000000000000000000000000000000000000000",
      pushed_at: Time.now,
      github_repository_id: github_repository_id,
      fork: false,
      # TODO: Assume the parsed manifest API is only for private manifests
      # However: that is not true, as of right now we call this api
      # for public manifests too, when identifying vulnerabilities.
      visibility_private: true,
    )
  end

  def manifest_type
    Types::Manifest.coerce(recognized.manifest_type)
  end

  def dependencies
    @dependencies ||= parsed_dependencies.map do |dependency|
      UnindexedDependency.new(
        dependency:                      dependency,
        manifest:                        recognized,
        requirements_set:                parsed_requirements_cache[dependency],
        package_cache:                   package_cache,
        has_dependencies_cache:          has_dependencies_cache,
        vulnerable_version_ranges_cache: vulnerable_version_ranges_cache,
      )
    end.sort
  end

  # Public: Is the recognized manifest in preview?
  # Returns boolean
  def in_preview?
    manifest_type.in?(DependencyGraph::MANIFEST_TYPE_PREVIEW) ||
      recognized.package_manager.in?(DependencyGraph::PACKAGE_MANAGER_PREVIEW)
  end

  def unsupported_vendored_manifest?
    VendorDetection.unsupported_vendored_manifest?(path, filename, manifest_type)
  end

  def file_path
    recognized.path.present? ? File.join(recognized.path, recognized.filename) : recognized.filename
  end

  def package_manager
    recognized.package_manager
  end

  # We expose `vendored?` via the API. For API consumers, `vendored?`
  # specificially indicates whether the manifest is an *unsupported* vendored
  # manifest.
  # This method will *not* do the Linguist calculation for whether a file is considered
  # to be in a "vendor/" style folder in a repo.
  alias_method :vendored?, :unsupported_vendored_manifest?

  private

  attr_reader :content, :recognized

  def parsed_dependencies
    @parsed_dependencies ||= recognized.dependencies.to_a
  end

  # Internal: A cache of packages in the manifest, batched to avoid N+1.
  #
  # Returns PackageCache<package_id, Package>
  def package_cache
    @package_cache ||= PackageCache.new(
      package_names:   parsed_dependencies.map(&:package_name),
      package_manager: recognized.package_manager,
    )
  end

  # Internal: A cache of `has_dependencies` flags for each dependency in the
  # manifest, batched to avoid N+1.
  #
  # HasDependenciesCache<package, Boolean>
  def has_dependencies_cache
    @has_dependencies_cache ||= HasDependenciesCache.new(
      requirements_by_package_func: -> { parsed_requirements_by_package },
      package_manager: recognized.package_manager,
    )
  end

  # Internal: A cache of vulnerable version ranges for each dependency in the
  # manifest, batched to avoid N+1.
  #
  # VulnerableVersionRangesCache<package, [VulnerableVersionRange]>
  def vulnerable_version_ranges_cache
    @vulnerable_version_ranges_cache ||= VulnerableVersionRangesCache.new(
      package_manager:              recognized.package_manager,
      requirements_by_package_name: parsed_requirements_by_package_name
    )
  end

  # Internal: A cache of `has_dependencies` flags for each dependency in the
  # manifest.
  #
  # Hash<dependency, RequirementSet>
  def parsed_requirements_cache
    @parsed_requirements ||= parsed_dependencies.map do |dependency|
      [
        dependency,
        parse_requirements(dependency.requirements, package_manager: recognized.package_manager)
      ]
    end.to_h
  end

  def parse_requirements(requirements, package_manager: nil)
    allow_named_versions = Types::PackageManager.allows_named_versions?(package_manager)
    set = Versioning::RequirementSet.deserialize(requirements, allow_named_versions: allow_named_versions)
    set.valid? ? set : Versioning::RequirementSet.wildcard
  end

  def parsed_requirements_by_package
    parsed_requirements_cache.map do |dependency, requirements_set|
      [
        package_cache[dependency.package_name],
        requirements_set
      ]
    end.to_h
  end

  def parsed_requirements_by_package_name
    parsed_requirements_cache.map do |dependency, requirements_set|
      [
        dependency.package_name,
        requirements_set
      ]
    end.to_h
  end

  # Internal: An eagerly loaded cache of package records for manifest
  # dependencies. The cache is used to avoid N+1 queries for each dependency.
  #
  # The cache is indexed by package name.
  class PackageCache
    def initialize(package_manager:, package_names:)
      @package_manager = package_manager
      @package_names   = package_names
    end

    def [](package_name)
      # We need to lower case the package_name when looking it up.
      # That is because MySQL is case-insensitive, thus
      # for the parsedManifest API be consistent with
      # the manifests API(which its results are stored in mysql),
      # we need to force a case while populating and looking up
      # the cache.
      # Note: eventually we should make the package_name column
      # case-sensitive. When we do that, we need to remove this
      # logic.
      #
      # tl;dr this is to maintain consistency with the manifests API
      cache[package_name.downcase]
    end

    private

    def cache
      @cache ||= Package
        .for_package_manager(@package_manager)
        .with_name(@package_names)
        .index_by { |package| package.name.downcase }
    end
  end

  # Internal: An eagerly loaded cache of vulnerable version ranges for manifest
  # dependencies. The cache is used to avoid N+1 queries for each dependency.
  #
  # The cache is indexed by package.
  class VulnerableVersionRangesCache
    def initialize(package_manager:, requirements_by_package_name:)
      @package_manager              = package_manager
      @requirements_by_package_name = requirements_by_package_name
    end

    def [](package_name)
      cache[package_name.downcase] || []
    end

    private

    attr_reader :package_manager, :requirements_by_package_name

    def cache
      @cache ||= build_cache
    end

    def build_cache
      package_names = requirements_by_package_name.map do |package_name, requirements_set|
        next unless package_name.present?
        next unless requirements_set.valid?

        package_name
      end.compact

      return {} if package_names.empty?

      VulnerableVersionRange
        .for_package_manager(package_manager)
        .where(package_name: package_names)
        .group_by { |vvr| vvr.package_name.downcase }
    end
  end

  # Internal: An eagerly loaded cache of 'has_dependencies` flags for manifest
  # dependencies. The cache is used to avoid N+1 queries for each dependency.
  #
  # For each dependency, we:
  #   1. Find the latest compatible package version
  #   2. Check to see if that package version has dependencies
  #
  # In practice, this involves a query of this shape:
  #
  #   SELECT package_id FROM package_versions
  #     INNER JOIN (
  #       SELECT MAX(encoded), package_id
  #       FROM package_versions
  #       WHERE <large batch of conditions, one per dependency>
  #     ) sub ON package_versions.encoded = sub.encoded
  #       AND package_versions.package_id = sub.package_id
  #   WHERE package_versions.id IN (
  #     SELECT dependent_id FROM package_dependent_specifications
  #   )
  #
  # The cache is indexed by package.
  class HasDependenciesCache
    def initialize(requirements_by_package_func:, package_manager: nil)
      @requirements_by_package_func = requirements_by_package_func
      @package_manager = package_manager
    end

    def [](package_id)
      cache[package_id]
    end

    private

    attr_reader :requirements_by_package

    def cache
      @cache ||= build_cache
    end

    def build_cache
      @requirements_by_package = @requirements_by_package_func.call
      return {} if Types::PackageManager.no_sub_dependencies?(@package_manager) || conditions.empty?

      join = <<~SQL
        INNER JOIN (#{subquery.to_sql}) sub
          ON #{PackageRelease.table_name}.encoded = sub.encoded
            AND #{PackageRelease.table_name}.package_id = sub.package_id
      SQL

      PackageRelease
        .joins(join)
        .where(id: PackageDependency.select(:dependent_id))
        .map { |release| [release.package_id, true] }
        .to_h
    end

    def subquery
      PackageRelease
        .group(:package_id)
        .select("MAX(encoded) as encoded, package_id")
        .where(conditions)
    end

    def conditions
      @conditions ||= requirements_by_package.map do |package, requirements_set|
        next unless package.present?
        next unless requirements_set.valid?

        lower = requirements_set.encoded_lower_bound
        upper = requirements_set.encoded_upper_bound

        PackageRelease.send(:sanitize_sql_array, [
          "(package_id = ? AND encoded BETWEEN ? AND ?)",
          package.id,
          lower,
          upper
        ])
      end.compact.join(" OR ")
    end
  end

  # Model used to expose dependency attributes to an API.
  # parsedManifest API will assign this object to a API::Types::Dependency.
  # ManifestDependency model is also returned as a API::Types::Dependency.
  class UnindexedDependency
    attr_reader :requirements_set

    def initialize(dependency:, manifest:, requirements_set:, package_cache:, has_dependencies_cache:, vulnerable_version_ranges_cache:)
      @manifest                        = manifest
      @dependency                      = dependency
      @requirements_set                = requirements_set
      @package_cache                   = package_cache
      @has_dependencies_cache          = has_dependencies_cache
      @vulnerable_version_ranges_cache = vulnerable_version_ranges_cache
    end

    def package_name
      dependency.package_name
    end

    def requirements
      requirements_set.serialize
    end

    def package_manager
      manifest.package_manager
    end

    def depends_on
      package_cache[package_name]
    end

    def vulnerable_version_ranges
      vulnerable_version_ranges_cache[package_name]
        .select { |range| requirements_set.overlap?(range.requirements_set) }
    end

    def scope
      return Types::Scope[:runtime] unless dependency.scope.present?

      Types::Scope.coerce(dependency.scope)
    end

    def package_github_repository_id
      depends_on&.github_repository_id
    end

    def has_dependencies?
      has_dependencies_cache[depends_on&.id]
    end
    alias :has_dependencies :has_dependencies?

    def <=>(other)
      package_name.downcase <=> other.package_name.downcase
    end

    private

    attr_reader :dependency, :manifest, :package_cache,
      :has_dependencies_cache, :vulnerable_version_ranges_cache
  end
end
