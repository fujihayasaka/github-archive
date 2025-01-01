# typed: false
# frozen_string_literal: true

module Registry
  module QueryHelper

    QUERYABLE_VISIBILITIES = %w(public private internal).freeze
    QUERYABLE_ECOSYSTEMS = %w(
      container
      docker
      maven
      npm
      nuget
      rubygems
      actions
    ).freeze

    SORT_TO_QUERY_PARAM = {
      "downloads_desc" => %w[downloads desc],
      "downloads_asc" => %w[downloads asc],
      "deleted_at_desc" => %w[deleted_at desc]
    }.freeze

    # Default to returning 30 search results
    def per_page_default
      30
    end

    # Overriding the maximum allowed offset into the search results to display all available results
    def max_offset_default
      10000 - per_page_default
    end

    # Public: Returns a list of packages based on the search parameters
    # provided. Uses elasticsearch to get search results through
    # Search::Queries::RegistryPackageQuery.
    #
    # Params:
    #  * current_user - The User who made this request.
    #  * user_session - The UserSession of the request.
    #  * owner - User or Organization that owns the package.
    #  * repo_id - The id of a Repository to scope the results to.
    #              Only used by Registry::PackagesController.
    #  * query - a query String
    #  * package_type - ecosystem filter string
    #  * visibility - visibility filter string
    #  * sort - Array of strings, see RegistryPackageQuery for sort fields.
    #
    # Returns: A mixed array of Registry::Package and PackageRegistry::Package.
    def packages_for_query(current_user:, user_session:, owner:, repo_id: nil, query: nil, package_type: nil, visibility: nil, sort: nil, page: 0, per_page: per_page_default, only_deleted_packages: false, excluded_packages: [], fail_fast: false, use_cached_versions: false, max_offset: max_offset_default, include_version_count: false)
      search = Search::QueryHelper.new(query, "RegistryPackages",
        current_user: current_user,
        user_session: user_session,
        highlight: false,
        owner: owner,
        repo_id: repo_id,
        query: query,
        package_type: package_type,
        visibility: visibility,
        only_deleted_packages: only_deleted_packages,
        excluded_packages: excluded_packages,
        sort: sort,
        per_page: per_page,
        page: page,
        max_offset: max_offset
      )["RegistryPackages"]

      # skip prune_results call from execute as prune_results make the redundant call to get_packages_metadata without the fail_fast metadata client.
      # get_packages_metadata is called below in this method.
      # Issue: https://github.com/github/c2c-package-registry/issues/5945
      results = search.execute(skip_prune_results: true)

      results_by_id = {}
      package_downloads = {}
      results.each do |result|
        package_downloads[result&.id] = result&.downloads
        results_by_id[result&.id] = result
      end
      package_ids = package_downloads.keys

      rms_ids, ar_ids = package_ids.partition { |id| id.start_with?("rms") }
      rms_ids = rms_ids.map { |str_id| str_id.sub(/rms-/, "").to_i }

      # Only ActiveRecord packages need to be filtered for visibility.
      # Authorization check for containers happens in registry-metadata.
      ar_packages = if only_deleted_packages
        owner.packages.where(id: ar_ids)
      else
        owner.packages.with_active_versions.where(id: ar_ids)
      end
      ar_packages = filter_packages_by_visibility(ar_packages, viewer: current_user)

      if use_cached_versions
        ar_packages.map! do |package|
          latest_version_name = results_by_id[package&.id&.to_s]&.latest_version
          version = Registry::PackageVersion.find_by(registry_package_id: package&.id, version: latest_version_name)
          Registry::PackageDecorator.new(package, version)
        end
      end

      ar_packages_by_id = ar_packages.index_by(&:id)

      collection = []
      # Fetch RMS packages
      if !GitHub.enterprise? || PackageRegistryHelper.ghes_registry_v2_enabled?
        begin
          rms_packages_by_id = if rms_ids.empty?
            {}
          else
            if fail_fast
              client = PackageRegistry::Twirp.fail_fast_metadata_client
            else
              client = PackageRegistry::Twirp.metadata_client
            end

            # If user is unauthenticated, we send a user_id of 0 to indicate anonymous access
            pm = client.get_packages_metadata(actor: current_user, package_ids: rms_ids, include_deleted: only_deleted_packages, exclude_latest_versions: use_cached_versions, include_version_count: include_version_count)
            .map { |p| [p.id, p] }
            .to_h

            # final sweep to be sure we did not get any active packages back from RMS to account for ES lag when the only_deleted flag is set
            pm = only_deleted_packages ? pm.delete_if { |_p_id, p| p.package.deleted_at.nil? } : pm

            # if we did not get versions from RMS we can try to get them from the ES document
            pm.each { |p_id, p| p.latest_version = results_by_id["rms-#{p_id}"]&.package&.latest_version } if use_cached_versions

            pm
          end
        # adding a RuntimeError rescue here to handle runtime errors.
        rescue PackageRegistry::Twirp::BaseError => e
          GitHub::Logger.info("Registry::QueryHelper.packages_for_query error occurred => #{e}")
          rms_packages_by_id = {}
        rescue RuntimeError => e
          GitHub::Logger.info("Registry::QueryHelper.packages_for_query RuntimeError => #{e}")
          rms_packages_by_id = {}
        rescue Faraday::TimeoutError => e
          GitHub::Logger.info("Registry::QueryHelper.packages_for_query Faraday::TimeoutError => #{e}")
          rms_packages_by_id = {}
        rescue Excon::Error::Timeout => e
          GitHub::Logger.info("Registry::QueryHelper.packages_for_query Excon::Error::Timeout => #{e}")
          rms_packages_by_id = {}
        end
      end

      # Set the package attribute for the result
      registry_package_doc = {}
      results.reject! do |result|
        doc_id_string = result.id
        if doc_id_string.start_with?("rms")
          doc_id = doc_id_string.sub(/rms-/, "").to_i
          result.package = rms_packages_by_id[doc_id]
          false
        else
          doc_id = doc_id_string.to_i
          registry_package = ar_packages_by_id[doc_id]
          if registry_package.nil?
            # stop removing packages from ES, because registry_package might not be there in ar_packages_by_id
            # but can still exist, under some other condition e.g. package might not have active_version,
            # but active record is there and is soft deleted.
            # https://github.com/github/c2c-package-registry/issues/6572
            # RemoveFromSearchIndexJob.perform_later("registry_package", doc_id, result.source["repo_id"])
            true
          else
            result.package = registry_package
            # Creating a new hash to mimic the search hash and passed to security_validation
            # This will be deprecated when all registries will move to v2
            registry_package_doc["_model"] = registry_package
            !search.security_validation registry_package_doc
          end
        end
      end

      collection = package_ids.map do |p_id|
        id_as_int = p_id.sub(/rms-/, "").to_i
        package = p_id.start_with?("rms") ? rms_packages_by_id[id_as_int] : ar_packages_by_id[id_as_int]
        next if package.blank? || package.owner.blank?
        package.total_download_count = package_downloads[p_id] || 0
        # if the user doesn't have read access to the repo, repo_id=0 effectively unlinks the package from the repo.
        package.package.repo_id = 0 if package.repository && !package.repository.readable_by?(current_user)
        package
      end.compact

      # iterate over collection and results to set the package_type_for_ui for each package from the result
      # This is needed because actions package info is not available in the collection list and we need to set the package_type_for_ui
      # for each package from the ES result
      collection.zip(results).each do |package, result|
        if package.respond_to?(:package_type_for_ui) && result&.source && result.source["package_type"]
          package.package_type_for_ui = result.source["package_type"]
        end
      end

      [results, collection]
    end

    private

    # Private: Filters a list of packages to those visible to a viewer.
    #
    # Params:
    #  * packages - an ActiveRecord relation of Registry::Package
    #  * viewer - a User, defaults to current_user
    #
    # Returns: a Array of packages that viewer can see.
    def filter_packages_by_visibility(packages, viewer: current_user)
      repo_ids = packages.pluck(:repository_id).uniq
      repos = Repository.where(id: repo_ids)
      repo_visibilities = Promise.all(repos.map { |r| r.async_readable_by?(viewer) }).sync
      visible_repo_ids = Set.new(repos.to_a.select.with_index { |_repo, i| repo_visibilities[i] }.map(&:id))

      packages.select { |p| visible_repo_ids.include?(p.repository_id) }
    end

    # Private: Are any of the query params present?
    #
    # Returns: Boolean
    def has_package_query_params?
      %w[ecosystem q visibility repo_name].any? { |p| params[p].present? }
    end

    # Private: Parses the ecosystem param and returns the string to be used
    # as the `package_type` param in Search::Queries::RegistryPackageQuery.
    # Returns nil for `all` since all package types are returned by default.
    #
    # Returns: String or nil
    def ecosystem_param
      raw = params[:ecosystem]&.downcase
      raw if QUERYABLE_ECOSYSTEMS.include?(raw)
    end

    # Private: Parses the visibility param and returns the string to be used
    # as the `visibility` param in Search::Queries::RegistryPackageQuery.
    #
    # Returns: String or nil
    def visibility_param
      raw = params[:visibility]&.downcase
      raw if QUERYABLE_VISIBILITIES.include?(raw)
    end

    # Private: Parses the sort_by param and returns the string to be used
    # as the `sort` param in Search::Queries::RegistryPackageQuery.
    #
    # Returns: [String] or nil
    def sort_param
      raw = params[:sort_by]&.downcase
      SORT_TO_QUERY_PARAM[raw]
    end
  end
end
