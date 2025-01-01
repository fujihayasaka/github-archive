# typed: true
# frozen_string_literal: true

module Search
  module Queries
    # The RegistryPackageQuery is used to search Registry Packages.
    #
    class RegistryPackageQuery < ::Search::Query

      # The set of fields that can be queried when performing a registry package search
      def self.field_list
        [:name, :sort, :user, :org, :owner, :repo, :package_type, :visibility, :topic].freeze
      end

      # A set of terms that have mutually exclusive values.
      def self.unique_field_list
        [:sort]
      end

      # The mapping of user-facing sort values to the corresponding values used
      # in the search index.
      SORT_MAPPINGS = {
        "downloads" => "downloads",
        "created" => "created_at",
        "updated" => "updated_at",
        "deleted_at" => "deleted_at",
      }.freeze

      DEFAULT_SORT = %w[downloads desc].freeze

      # The maximum number of characters returned in the highlighted fragments.
      FRAGMENT_SIZE = 200

      # Construct a new RegistryPackageQuery instance that will highlight search results
      # by default.
      def initialize(opts = {}, &block)
        super(opts, &block)
        @index                   = Elastomer::Indexes::RegistryPackages.new
        @repo_id                 = opts.fetch(:repo_id, nil)
        @owner                   = opts.fetch(:owner, nil)
        @package_type            = opts.fetch(:package_type, nil)
        @only_deleted_packages   = opts.fetch(:only_deleted_packages, false)
        @excluded_packages       = opts.fetch(:excluded_packages, [])
        @visibility              = opts.fetch(:visibility, nil)
        @original_package_type   = qualifiers[:package_type].dup
      end

      # Internal: Returns the Array of advanced search qualifiers supported by
      # this query type.
      def qualifier_fields
        self.class.field_list
      end

      # Internal: Returns the Array of fields that support aggregation queries.
      def aggregation_fields
        [:package_type, :package_subtype]
      end

      # Internal: Returns a Hash that will be passed as URL params for the query.
      def query_params
        {
          index: Elastomer.env.index_name("packages"),
          type: "registry_package"
        }.tap do |params|
          params[:routing] = @repo_id if @repo_id
        end
      end

      # Internal: Returns the Array of field names that will be queried.
      def query_fields
        @query_fields ||= ["name^1.2", "name.ngram", "summary", "body", "original_name", "original_name.ngram"]
      end

      # Internal: Constructs the search query based on the `query` attribute.
      #
      # Returns the search query Hash.
      def query_doc
        return unless escaped_query.present?

        {
          function_score: {
            query: {
              query_string: {
                query:            escaped_query,
                fields:           query_fields,
                phrase_slop:      10,
                default_operator: "AND",
                analyzer:         "texty_search",
              },
            },
            # This function reduces the score of documents that haven't been
            # updated recently. A document not modified in 24 weeks will have its
            # score reduced by half. Look at updated_at so that old registry packages
            # that get renewed aren't punished for having an old created_at.
            exp: {
              updated_at: {
                scale:  "168d",
                offset: "14d",
                decay:  0.5,
              },
            },
          },
        }
      end

      # Internal: Returns the sorting options Array.
      def build_sort
        return if sort.blank?

        ary = build_sort_section(sort, "_score", SORT_MAPPINGS)
        ary.each do |item|
          next unless item.is_a?(Hash)

          key = item.keys.first
          if "created_at" == key || "updated_at" == key || "deleted_at" == key
            order = item[key]
            item[key] = { "order" => order, "unmapped_type" => "date" }
          end
        end

        ary
      end

      # Returns the default sort ordering to use in the absence of a query or
      # any other sort information.
      def default_sort
        DEFAULT_SORT
      end

      # Internal: Build the filters required for the query.
      #
      # Returns the Hash of filter hashes.
      def filter_hash
        return @filter_hash if defined? @filter_hash

        filters = {}
        filters[:created_at] = builder.date_range_filter(:created_at, :created)
        filters[:updated_at] = builder.date_range_filter(:updated_at, :updated)

        qualifiers[:user].clear.must(@owner.login) if @owner && @owner.is_a?(User)

        filters.delete_if { |_, filter| filter.nil? || (filter.valid? && filter.blank?) }

        @filter_hash = filters
      end

      def build_query_filter
        filter = ::Search::Filters::BoolFilter.new(filter_hash, aggregations)
        query_filter = filter.build

        query_filter ||= { bool: {} }
        query_filter[:bool][:must] = build_must_filters
        query_filter[:bool][:must_not] = package_filter.must_not if package_filter.must_not.present?

        if GitHub.flipper[:search_action_packages].enabled?(current_user)
          # combine build_must_not_filters and query_filter[:bool][:must_not] to query_filter[:bool][:must_not]
          query_filter[:bool][:must_not] = [query_filter[:bool][:must_not], build_must_not_filters].flatten.compact
        end

        query_filter[:bool][:must] = [query_filter[:bool][:must], package_filter.must].flatten.compact

        # If a package is scoped to a user/org/repo, then the must filter will cover the results and the
        # shoulds are unnecessary. However, if it's a global scoped request, then the package should match
        # at least one of the conditions in the should block.
        if package_filter.global_scoped_query?
          query_filter[:bool][:should] = package_filter.should
          query_filter[:bool][:minimum_should_match] = 1
        end

        query_filter
      end

      # package_type as URL query param for old search - via @package_type
      # package_type passed via qualifiers for new code search UI
      def build_must_filters
        if @package_type
          # in case of package_type passed via URL, we are giving highest priority to it
          # the if condition branches below it works on original_package_type, so we need to update that as well.
          qualifiers[:package_type].clear.must(@package_type)
          @original_package_type.clear.must(@package_type)
        end
        qualifiers[:visibility].clear.must(@visibility) if @visibility


        if GitHub.flipper[:search_action_packages].enabled?(current_user)
          if @original_package_type.present? && @original_package_type.must.present? && @original_package_type.must.include?("actions")
            dup_qualifier = @original_package_type.dup
            qualifiers[:package_subtype] = dup_qualifier

            # we receive qualifiers[:package_type] as actions from the UI so this needs to map to package_type:container and package_subtype:actions
            qualifiers[:package_type].map_all! do |val|
              val == "actions" ? "container" : val
            end
          end
        end

        must_filters = []
        must_filters << builder.term_filter(:package_type).must
        # do if search_action_packages is enabled
        if GitHub.flipper[:search_action_packages].enabled?(current_user)
          must_filters << builder.term_filter(:package_subtype).must
        end
        must_filters << builder.term_filter(:visibility).must
        must_filters << builder.term_filter(
          :applied_topics, :topic,
          execution: :and,
          missing: :none
        ) { |topic| topic.downcase }.must

        must_filters.compact
      end

      # only called for action packages when search_action_packages is enabled
      def build_must_not_filters
        if @original_package_type.present? && @original_package_type.must.present? && @original_package_type.must.include?("container")
          dup_qualifier = @original_package_type.dup
          dup_qualifier.must.clear
          dup_qualifier.must_not("actions")
          qualifiers[:package_subtype] = dup_qualifier
        end
        must_not_filters = []
        must_not_filters << builder.term_filter(:package_subtype).must_not
        must_not_filters.compact
      end

      # Internal: Returns the highlight Hash.
      def build_highlight
        {
          encoder: :html,
          type: "plain",
          fields: {
            name: { number_of_fragments: 0 },
            "name.ngram": { number_of_fragments: 0 },
          },
        }
      end

      def package_filter
        @package_filter ||= builder.registry_filter(
          current_user,
          @owner&.id,
          @repo_id,
          "registry",
          user_session: user_session,
          package_type: @package_type,
          only_deleted_packages: @only_deleted_packages,
          excluded_packages: @excluded_packages
        )
      end

      # Internal: Prune results and then run the `normalizer` on the results
      # if one was provided.
      #
      # results - An Array of hits from the search index.
      #
      # Returns the normalized Array of hits.
      def normalize(results)
        prune_results(results) unless @results_pruned
        super(results)
      end

      # Internal: Take the array of registry package results and remove those for which
      # the registry package no longer exists. We will only perform this pruning in test
      # and production; development mode is for testing out everything.
      #
      # results - An Array of hits from the search index.
      #
      # Returns the pruned Array of hits.
      def prune_results(results)
        package_ids = results.map { |h| h["_id"] }
        rms_ids, ar_ids = package_ids.partition { |id| id.start_with?("rms") }
        rms_ids = rms_ids.map { |str_id| str_id.sub(/rms-/, "").to_i }

        # Get all AR Packages based on results
        ar_packages = Registry::Package.includes(:owner, :repository).where(id: ar_ids).index_by(&:id)
        rms_packages_by_id = {}

        # Get all RMS Packages based on results
        if !GitHub.enterprise? || PackageRegistryHelper.ghes_registry_v2_enabled?
          begin
            unless rms_ids.empty?
              rms_packages_by_id = PackageRegistry::Twirp.metadata_client.get_packages_metadata(actor: current_user, package_ids: rms_ids, include_deleted: @only_deleted_packages, exclude_latest_versions: true)
              .each_with_object({}) { |package, accumulator| accumulator[package.id] = package }
            end
          rescue PackageRegistry::Twirp::BaseError
            rms_packages_by_id = {}
          end
        end

        results.delete_if do |result|
          owner = User.find_by_login(result["_source"]["namespace"])
          if owner != nil && !PackageRegistryHelper.allow_access_to_actor?(owner, current_user)
            true
          else
            doc_id_string = result["_id"]
            if doc_id_string.start_with?("rms")
              doc_id = doc_id_string.sub(/rms-/, "").to_i
              result["_model"] = rms_packages_by_id[doc_id]
              false
            else
              doc_id = doc_id_string.to_i
              registry_package = ar_packages[doc_id]

              if registry_package.nil? && !Rails.env.development?
                RemoveFromSearchIndexJob.perform_later("registry_package", doc_id, result["_routing"])
                true
              else
                result["_model"] = registry_package
                !security_validation result
              end
            end
          end
        end
      end

      # Internal: validate that the user is allowed to see the given search
      # result document.
      #
      # doc - The search result Hash
      #
      # Returns a boolean indicating visibility.
      def security_validation(doc)
        return true unless registry_package = doc["_model"]

        repo = registry_package.repository
        return true if package_filter.accessible_repository?(repo)

        GitHub.dogstats.increment("search.query.errors.security", { tags: ["index:#{index.name}"] })
        false
      end
    end
  end
end
