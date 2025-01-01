# typed: true
# frozen_string_literal: true

module AdvisoryDB::GlobalAdvisoriesApiHelper
  extend T::Sig

  MAX_PACKAGES_PER_QUERY = 1000
  MAX_PACKAGES_PER_BATCH = 100
  SORT_PARAMS = %w[before after per_page page sort direction]

  # Simple regex to ensure we are splitting a package string and then a version string,
  # with one '@' in between them. This is used to avoid accidently splitting
  # a namespaced package name (ex: @place/package@1.0.0).
  PACKAGE_VERSION_REGEX = /\A(?<package>\S+)@(?<version>\S+)\z/


  def vuln_ids_affecting_packages(affects:, base_scope: Vulnerability.disclosed, current_user: nil, request_params: nil, backend: nil)
    return unless affects

    query_start_time = GitHub::Dogstats.monotonic_time
    is_package_versions_query = T.let(false, T::Boolean)
    GitHub.dogstats.increment("global_advisories_api.affected_packages_query")
    GitHub.dogstats.distribution("global_advisories_api.affected_packages_query_size", affects.count)

    cache_key = request_params ? vuln_ids_cache_key(request_params) : vuln_ids_cache_key({ affects: affects })

    vuln_ids = GitHub.cache.fetch(cache_key, stats_key: "global_advisories_api.affected_packages.cache") do
      # we obtain a hash that pairs up package names with any versions the user has
      # decided to query for.
      affected_packages_with_versions = parse_affected_packages(affects.first(MAX_PACKAGES_PER_QUERY))
      package_names = affected_packages_with_versions.keys

      all_vuln_ids = T.let([], T::Array[Integer])
      package_version_vuln_ids = T.let([], T::Array[Integer])

      # we first add vulnerabilities that apply to packages that are being queried without a
      # specific version attached to them.
      packages_all_versions = affected_packages_with_versions.select { |_, versions| versions.empty? }
      packages_all_versions_names = packages_all_versions.keys
      packages_all_versions_names.in_groups_of(MAX_PACKAGES_PER_BATCH, false) do |packages|
        base_scope.where(vulnerable_version_ranges: { affects: packages }).in_batches(of: 500) do |batch|
          all_vuln_ids += batch.ids
        end
      end

      # then iterate through the rest and check if the vulnerability's ranges
      # affect any of the requested package versions.
      # feed ranges into .affects_package_versions? to avoid loading them again
      package_versions = affected_packages_with_versions.values.flatten
      is_package_versions_query = package_versions.any?

      if is_package_versions_query
        GitHub.dogstats.increment("global_advisories_api.affected_package_versions_query")
        GitHub.dogstats.distribution("global_advisories_api.affected_package_versions_query_size", package_versions.count)

        packages_select_versions_names = package_names - packages_all_versions.keys

        packages_select_versions_names.in_groups_of(MAX_PACKAGES_PER_BATCH, false) do |packages|
          base_scope.where(vulnerable_version_ranges: { affects: packages }).in_batches(of: 100) do |batch|
            package_version_vuln_ids += batch.select { |vuln| vuln.affects_package_versions?(affected_packages_with_versions, vuln.vulnerable_version_ranges) }.map(&:id)
          end
        end

        all_vuln_ids += package_version_vuln_ids
        GitHub.dogstats.distribution("global_advisories_api.affected_package_versions_query_results", package_version_vuln_ids.uniq.count, tags: ["backend:#{backend}"])
      end

      all_vuln_ids = all_vuln_ids.uniq
      GitHub.dogstats.distribution("global_advisories_api.affected_packages_query_results", all_vuln_ids.count, tags: ["backend:#{backend}"])

      all_vuln_ids
    end

    elapsed = GitHub::Dogstats.duration(query_start_time)
    GitHub.dogstats.distribution("global_advisory_api.affected_packages_query.duration", elapsed, tags: ["package_versions:#{is_package_versions_query}"])

    vuln_ids
  end

  sig { params(param_value: T.any(Array, String)).returns(T::Hash[String, T::Array[String]]) }
  def parse_affected_packages(param_value)
    packages = list_to_array(param_value)
    affected_packages = {}

    packages.each do |package|
      parsed = package.match(PACKAGE_VERSION_REGEX)
      name, version = parsed ? parsed.captures : [package, nil]
      affected_packages[name] ||= []
      affected_packages[name] << version if version
    end

    affected_packages
  end

  def querying_package_versions?(param_value)
    return false unless param_value

    affected_packages = list_to_array(param_value)
    affected_packages.any? { |package| package.match?(PACKAGE_VERSION_REGEX) }
  end

  sig { params(list: T.any(Array, String)).returns(Array) }
  def list_to_array(list)
    if list.is_a?(String)
      list.split(",")
    else
      list
    end
  end

  def vuln_ids_cache_key(params)
    filter_params = params.except(*SORT_PARAMS)
    filter_params_string = filter_params.sort.flatten.join(",")
    hash = Digest::SHA256.hexdigest(filter_params_string)
    # Slice off the second digit of minute to create 10 minute intervals
    # For example, hits at :54 and :58 in an hour have the same key suffix, `5`.
    # A resulting key timestamp on 2023-01-01 @ hour 01 for those time times
    # would be 20230101T015
    time = Time.now.strftime("%Y%m%dT%H%M")[0...-1]

    ["global_advisories_api_affected_packages", time, hash].join(":")
  end

  def sort_advisories(query, sort_by: :published, direction: :desc, current_user: nil)
    order_by = :"#{sort_by}_#{direction}"
    order_clause = case order_by
    when :published_asc
      { published_at: :asc }
    when :published_desc
      { published_at: :desc }
    when :reviewed_asc
      { reviewed_at: :asc }
    when :reviewed_desc
      { reviewed_at: :desc }
    when :updated_asc
      { updated_at: :asc }
    when :updated_desc
      { updated_at: :desc }
    else
      { published_at: :desc }
    end

    if GitHub.flipper[:advisory_db_epss_user_facing].enabled?(current_user)
      case order_by
      when :epss_percentage_asc
        query = query.joins(:cve_epss).order("cve_epss.percentage ASC")
      when :epss_percentage_desc
        query = query.joins(:cve_epss).order("cve_epss.percentage DESC")
      when :epss_percentile_asc
        query = query.joins(:cve_epss).order("cve_epss.percentile ASC")
      when :epss_percentile_desc
        query = query.joins(:cve_epss).order("cve_epss.percentile DESC")
      else
        query = query.order(order_clause)
      end
    else
      query = query.order(order_clause)
    end

    query
  end
end
