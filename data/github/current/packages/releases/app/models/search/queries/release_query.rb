# typed: true
# frozen_string_literal: true

module Search
  module Queries
    class ReleaseQuery < ::Search::Query

      # The set of fields that can be queried when performing a release search
      QUERY_FIELDS = [:tag_name, :name, :body].freeze

      # The set of qualifiers that can be used on a query phrase
      def self.field_list
        [:draft, :prerelease, :tag, :created].freeze
      end

      # On normalize, remove duplicate occurrences of these qualifiers (right-most wins)
      def self.unique_field_list
        [:draft, :tag, :prerelease, :created].freeze
      end

      # The default sort ordering to use
      DEFAULT_SORT = %w[draft desc created_day desc version desc prerelease asc tag desc].freeze

      # The user-facing sort values with their corresponding field value
      SORT_MAPPINGS = {
        "draft"       => "draft",
        "prerelease"  => "prerelease",
        "created"     => "created_at",
        "created_day" => "created_day",
        "tag"         => "tag_name.raw",
        "version"     => %w[version_major version_minor version_patch],
        "name"        => "name",
      }.freeze

      # The maximum number of highlight fragments returned. Set number high enough to include all matches.
      BODY_FRAGMENT_COUNT = 1000
      RELEASE_NAME_FRAGMENT_COUNT = 50

      # The maximum number of results to return for a signed in user.
      SIGNED_IN_MAX_OFFSET = 10_000


      # Construct a ReleaseQuery.
      #
      # opts - The options Hash.
      #   :repository - The repository to limit the search to
      #   :current_user - The current user to check permissions
      #   :allow_drafts - Whether to allow drafts in the search results. This is passed in via param
      #                   to work with the fact that the UI and API have different permissions logic for this.
      #
      def initialize(opts = {}, &block)
        opts[:max_offset] ||= SIGNED_IN_MAX_OFFSET if opts[:current_user] # if not specified this defaults to Query::max_offset_default

        super(opts, &block)

        @index = Elastomer::Indexes::Releases.new

        @repository = opts[:repository]
        @allow_drafts = opts.fetch(:allow_drafts, false)
      end

      # Internal: Returns the Array of advanced search qualifiers supported by
      # this query type.
      def qualifier_fields
        self.class.field_list
      end

      # Internal: Constructs the actual `:query` portion of the query
      # document. This will later be wrapped in a filtered query if search
      # qualifiers were also used.
      #
      # Returns the search query Hash.
      def query_doc
        if escaped_query.present?
          {
            function_score: {
              query: {
                query_string: {
                  query:            escaped_query,
                  fields:           query_fields,
                  default_operator: "AND",
                },
              },
              score_mode: "multiply",
            },
          }
        end
      end

      # Internal: Returns the Array of field names that will be queried.
      def query_fields
        QUERY_FIELDS
      end

      # Internal: Returns a Hash that will be passed as URL params for the query.
      def query_params
        { type: "release" }
      end

      # Internal: Returns the highlight Hash.
      def build_highlight
        {
          type: "plain",
          fields: {
            tag_name: {
              number_of_fragments: 0,   # Force the full tag_name to be displayed
              pre_tags: ["<mark class='hx_keyword-hl'>"], #use custom styling for highlighting contrast in dark themes
              post_tags: ["</mark>"]
            },
            name: {
              # Set the number of fragments to include all matches but limit each fragment to just the matching query token
              number_of_fragments: RELEASE_NAME_FRAGMENT_COUNT,
              fragment_size: 0,
              pre_tags: [""],          # Do not wrap query tokens in tags
              post_tags: [""],
            },
            body: {
              # Set the number of fragments to include all matches but limit each fragment to just the matching query token
              number_of_fragments: BODY_FRAGMENT_COUNT,
              fragment_size: 0,
              pre_tags: ["<mark>"],
              post_tags: ["</mark>"],
            }
          }
        }
      end

      # Internal: Returns the sorting options Array.
      def build_sort
        build_sort_section(sort || default_sort, SORT_MAPPINGS)
      end

      # The default sort ordering to use if not specified.
      def default_sort
        DEFAULT_SORT
      end

      # Filter results by repository and apply any qualifiers.
      def filter_hash
        return @filter_hash if defined? @filter_hash

        qualifiers[:draft].clear.must(false) unless @allow_drafts

        filters = {}
        filters[:repo_id] = builder.repository_filter(nil, @repository.id, "metadata", user_session: user_session, ip: remote_ip)

        filters[:draft] = builder.term_filter(:draft, singular: true) do |value|
          case value.to_s
          when /\Atrue\z/i; true
          when /\Afalse\z/i; false
          else nil
          end
        end

        filters[:prerelease] = builder.term_filter(:prerelease, singular: true) do |value|
          case value.to_s
          when /\Atrue\z/i; true
          when /\Afalse\z/i; false
          else nil
          end
        end

        filters[:created_at] = builder.date_range_filter(:created_at, :created)

        filters[:tag_name] = builder.term_filter(:tag_name, :tag)

        @filter_hash = filters
      end

      # Internal: Prune results and then run the `normalizer` on the results
      # if one was provided.
      #
      # results - An Array of hits from the search index.
      #
      # Returns the normalized Array of hits with a _model entry on the hash.
      def normalize(results)
        results = prune_results(results) unless @results_pruned
        super(results)
      end

      # Internal: Take the array of release results and remove those that
      # no longer exist in the database.
      #
      # results - An Array of hits from the search index.
      #
      # Returns the pruned Array of hits.
      def prune_results(results)
        release_ids = results.map { |h| h["_id"] }
        releases = Releases::Public.load_releases_and_prefill_tags(release_ids, @repository)
        releases = releases.index_by(&:id)

        releases_to_delete = {}
        promises = results.map do |release_hash|
          release_id = release_hash["_id"].to_i
          release = releases[release_id]

          if release.nil?
            GitHub.dogstats.increment("search.query.exclude.nil", { tags: ["index:#{index.name}"] })
            releases_to_delete[release_id] = true
          elsif !release.is_searchable?(log_reason: true)
            GitHub.dogstats.increment("search.query.exclude.is_searchable", { tags: ["index:#{index.name}"] })
            releases_to_delete[release_id] = true
          else
            release.async_readable_by?(current_user).then do |is_readable|
              if is_readable
                release_hash["_model"] = release
              else
                releases_to_delete[release_id] = true
              end
            end
          end
        end
        Promise.all(promises).sync

        pruned_results = results.reject do |release_hash|
          release_id = release_hash["_id"].to_i
          releases_to_delete[release_id]
        end

        pruned_results
      end
    end
  end
end
