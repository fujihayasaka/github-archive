module Queries
  class RepositoryPackageReleasesQuery
    include OrderedQuery

    delegate :each, to: :results

    SORT_BY_FIELDS = {
      PUBLISHED_AT: {
        field: "#{PackageRelease.table_name}.published_at",
        order_value: -> (node) { node.package_release.published_at&.to_fs(:db) },
        order_by: -> (scope, direction) {
          direction == :desc ? scope.recently_published : scope.least_recently_published
        }
      },
      UPDATED_AT: {
        field: "#{PackageRelease.table_name}.updated_at",
        order_value: -> (node) { node.package_release.updated_at.to_fs(:db) },
        order_by: -> (scope, direction) {
          direction == :desc ? scope.recently_updated : scope.least_recently_updated
        }
      },
      DEPENDENTS: {
        field: "dependents_count",
        having: true,
        order_value: -> (node) { node.dependents_count.to_i },
        order_by: -> (scope, direction) { scope.order("dependents_count #{direction}") }
      },
      VULNERABILITIES: {
        field: "IFNULL(#{Views::PackageReleaseVulnerabilitiesCount.table_name}.total_count, 0)",
        order_value: -> (node) { node.vulnerabilities_count.to_i },
        order_by: -> (scope, direction) { scope.order("#{Views::PackageReleaseVulnerabilitiesCount.table_name}.total_count #{direction}") }
      },
    }.freeze

    SORT_BY = {
      NEWEST: SORT_BY_FIELDS[:PUBLISHED_AT].merge({ direction: :desc }),
      OLDEST: SORT_BY_FIELDS[:PUBLISHED_AT].merge({ direction: :asc }),
      RECENTLY_UPDATED: SORT_BY_FIELDS[:UPDATED_AT].merge({ direction: :desc }),
      LEAST_RECENTLY_UPDATED: SORT_BY_FIELDS[:UPDATED_AT].merge({ direction: :asc }),
      MOST_DEPENDENTS: SORT_BY_FIELDS[:DEPENDENTS].merge({ direction: :desc }),
      LEAST_DEPENDENTS: SORT_BY_FIELDS[:DEPENDENTS].merge({ direction: :asc }),
      MOST_VULNERABILITIES: SORT_BY_FIELDS[:VULNERABILITIES].merge({ direction: :desc }),
      LEAST_VULNERABILITIES: SORT_BY_FIELDS[:VULNERABILITIES].merge({ direction: :asc }),
      DEFAULT: {
        direction: :asc,
        order_by: -> (scope, direction) { scope },
        order_value: -> {}
      }
    }.freeze

    def initialize(owner_ids:, name: nil, sort_by: "DEFAULT", version: nil, package_manager: nil, vulnerable: false, exact_match: false, license: nil, severity: nil, dependent_name: nil)
      @owner_ids = owner_ids
      @name = name
      @version = version if name?
      @package_manager = package_manager
      @sort_by = sort_by
      @vulnerable = vulnerable
      @exact_match = exact_match
      @severity = severity
      @license = license
      @dependent_name = dependent_name

      @allow_named_versions = package_manager.nil? || Types::PackageManager.allows_named_versions?(package_manager)
    end

    def results
      return @results if defined?(@results)

      @results = ActiveRecord::Base.connected_to(role: :reading) do
        results = scope
        results = apply_cursors(results)
        results = apply_limits(results)
        PackageReleaseDependent.wrap(results)
      end
    end

    def severity?
      severity.present?
    end

    def version?
      version.present?
    end

    def license?
      license.present?
    end

    def numeric?(version)
      Float(version) != nil rescue false
    end

    def version_set
      # Checks to see if exact version is passed without version specifier for exact versions
      # Strip version string for any whitespace that might throw off our check for exact version
      # Allows for (= version) and (version) to be both processed without hassle
      if version?
        @version = version.strip
        @version = "= #{version}" if version[0].match?(/\w/)
      end

      @version_set ||= Versioning::RequirementSet
        .deserialize(version, **{
          on_error: ->(range) {
            # if version set parsed contains errors don't filter results by version
            # set version to nil here so query ignores version when scoping results
            version = nil
          },
          allow_named_versions: @allow_named_versions,
        })
    end

    def package_manager?
      package_manager.present?
    end

    def name?
      name.present?
    end

    def total_count
      @total_count ||= base_scope.count("distinct #{PackageRelease.table_name}.id")
    end

    def vulnerability_severities
      @vulnerability_counts ||= begin
        severity_counts = base_scope
          .vulnerable
          .select("SUM(#{Views::PackageReleaseVulnerabilitiesCount.table_name}.low_count) as low_count,
                   SUM(#{Views::PackageReleaseVulnerabilitiesCount.table_name}.moderate_count) as moderate_count,
                   SUM(#{Views::PackageReleaseVulnerabilitiesCount.table_name}.high_count) as high_count,
                   SUM(#{Views::PackageReleaseVulnerabilitiesCount.table_name}.critical_count) as critical_count,
                   SUM(CASE WHEN #{Views::PackageReleaseVulnerabilitiesCount.table_name}.low_count > 0
                       THEN #{Views::PackageReleaseDependentCount.table_name}.count
                       ELSE 0 END) as dependents_low_count,
                   SUM(CASE WHEN #{Views::PackageReleaseVulnerabilitiesCount.table_name}.moderate_count > 0
                       THEN #{Views::PackageReleaseDependentCount.table_name}.count
                       ELSE 0 END) as dependents_moderate_count,
                   SUM(CASE WHEN #{Views::PackageReleaseVulnerabilitiesCount.table_name}.high_count > 0
                       THEN #{Views::PackageReleaseDependentCount.table_name}.count
                       ELSE 0 END) as dependents_high_count,
                   SUM(CASE WHEN #{Views::PackageReleaseVulnerabilitiesCount.table_name}.critical_count > 0
                       THEN #{Views::PackageReleaseDependentCount.table_name}.count
                       ELSE 0 END) as dependents_critical_count")
        PackageReleaseVulnerabilitySeverity.wrap(severity_counts)
      end
    end

    def licenses
      @license_counts ||= begin
        license_type_counts = base_scope
          .select("#{PackageRelease.table_name}.license, COUNT(#{PackageRelease.table_name}.id) as licenses_count")
          .where("#{PackageRelease.table_name}.license is NOT NULL")
          .group("#{PackageRelease.table_name}.license")
        PackageReleaseLicense.wrap(license_type_counts)
      end
    end

    def sorter
      @sorter ||= SORT_BY.fetch(sort_by.to_s.to_sym, SORT_BY[:DEFAULT])
    end

    # Get the value of the node for the ordering condition that is being used
    def order_by_value(node)
      sorter[:order_value].call(node)
    end

    def id_column
      "#{PackageRelease.table_name}.id"
    end

    # Get the order by condition for the configured sort by
    def order_by_condition
      sorter[:field]
    end

    def add_order_by_conditions(scope, conditions, values)
      if sorter[:having]
        scope.having(conditions, *values)
      else
        scope.where(conditions, *values)
      end
    end

    # Get the order by direction for the configured sort by
    def order_by_direction
      sorter[:direction]
    end

    def scope
      return @scope if @scope

      # Get the dependent and vulnerability counts
      @scope = base_scope.select("
        #{PackageRelease.table_name}.*,
        #{Views::PackageReleaseVulnerabilitiesCount.table_name}.total_count as total_vulnerabilities_count,
        SUM(#{Views::PackageReleaseDependentCount.table_name}.count) as dependents_count
      ")

      @scope = @scope.group("#{PackageRelease.table_name}.id")

      # Prefill packages since github_repository_id is stored there
      @scope = @scope.preload(:package)

      # Sort by specified direction
      @scope = sorter[:order_by].call(@scope, sorter[:direction])

      # Add secondary ordering by id to keep cursors stable
      @scope = @scope.order("#{PackageRelease.table_name}.id #{sorter[:direction]}")
    end

    def base_scope
      return @base_scope if @base_scope

      @base_scope =
        PackageRelease
          .left_outer_joins(:vulnerability_count_view)
          .joins("INNER JOIN #{Views::PackageReleaseDependentCount.table_name} ON #{Views::PackageReleaseDependentCount.table_name}.package_release_id = #{PackageRelease.table_name}.id")
          .merge(Views::PackageReleaseDependentCount.where(github_owner_id: owner_ids))

      # scope results by package manager if package manager argument is passed
      @base_scope = @base_scope.where(package_manager: package_manager.serialize) if package_manager?

      # scope results by exact name, if name and exact_match arguments are passed as true, else do substring match
      if name?
        @base_scope = if exact_match
                        @base_scope.where(package_name: name)
        else
          @base_scope.where("#{PackageRelease.table_name}.package_name LIKE :substring", { substring: "%#{ActiveRecord::Base.sanitize_sql_like(name)}%" })
        end
      end

      # scope results with vulnerabilities if we want them
      @base_scope = @base_scope.vulnerable if vulnerable?

      # scope results to specific vulnerability severity
      @base_scope = @base_scope.with_severity(severity) if severity?

      # scope results to specific licenses
      @base_scope = @base_scope.matching_license(license) if license?

      # scope results by version of package release if version range argument passed
      @base_scope = @base_scope.matching_requirement_set(version_set) if version?

      @base_scope = @base_scope.unscope(:order)
      @base_scope
    end

    attr_reader :owner_ids, :name, :sort_by, :package_manager, :vulnerable, :exact_match, :severity, :license, :dependent_name
    attr_accessor :version
    alias :vulnerable? :vulnerable
  end

  class PackageReleaseDependent
    attr_accessor :package_release, :dependents_count, :vulnerabilities_count
    delegate :id, to: :package_release

    def self.wrap(results)
      results.map do |r|
        dependent = PackageReleaseDependent.new
        dependent.package_release = r
        dependent.dependents_count = r.dependents_count
        dependent.vulnerabilities_count = r.total_vulnerabilities_count || 0

        dependent
      end
    end
  end

  class PackageReleaseVulnerabilitySeverity
    attr_reader :severity, :total_count, :dependents_count

    def initialize(severity, total_count, dependents_count)
      @severity = severity
      @total_count = total_count
      @dependents_count = dependents_count
    end

    def self.wrap(results)
      rollup = results.first
      severities = []

      if rollup.low_count && rollup.low_count > 0
        severities << PackageReleaseVulnerabilitySeverity.new(:low, rollup.low_count, rollup.dependents_low_count)
      end

      if rollup.moderate_count && rollup.moderate_count > 0
        severities << PackageReleaseVulnerabilitySeverity.new(:moderate, rollup.moderate_count, rollup.dependents_moderate_count)
      end

      if rollup.high_count && rollup.high_count > 0
        severities << PackageReleaseVulnerabilitySeverity.new(:high, rollup.high_count, rollup.dependents_high_count)
      end

      if rollup.critical_count && rollup.critical_count > 0
        severities << PackageReleaseVulnerabilitySeverity.new(:critical, rollup.critical_count, rollup.dependents_critical_count)
      end

      severities
    end
  end

  class PackageReleaseLicense
    attr_accessor :license, :total_count

    def self.wrap(results)
      combine_other_licenses(results).map do |result|
        wrapped = PackageReleaseLicense.new
        wrapped.license = result.license
        wrapped.total_count = result.licenses_count
        wrapped
      end
    end

    # Combine all non-valid license values into a single Other license grouping
    # with a rollup count spanning all non-valid values.
    def self.combine_other_licenses(results)
      license_values = Set.new(API::Enums::License.values.values.map(&:value))
      other_licenses_release = nil

      results.select do |release|
        next true if license_values.include?(release.license)

        if other_licenses_release
          other_licenses_release.licenses_count += release.licenses_count
          false
        else
          other_licenses_release = release
          other_licenses_release.license = "Other"
          true
        end
      end
    end
  end
end
