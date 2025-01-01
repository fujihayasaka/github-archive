# typed: true
# frozen_string_literal: true

module Search
  module Queries

    class GistQuery < ::Search::Query

      # The set of fields that can be queried when performing a repository search
      def self.field_list
        [
          :in, :sort, # ES fields
          :user, :public, :anon, :fork, :forks, :stars, :created, :updated, # Gist fields
          :filename, :extension, :language, :size # File contents fields
        ].freeze
      end

      # The mapping of user-facing sort values to the corresponding values used
      # in the search index.
      SORT_MAPPINGS = {
        "stars"   => "stars",
        "forks"   => "forks",
        "updated" => "updated_at",
      }.freeze

      # The default sort ordering to use in the absence of a query or any
      # other sort information
      DEFAULT_SORT = %w[stars desc].freeze

      # Construct a GistQuery.
      #
      # opts - The options Hash.
      #
      def initialize(opts = {}, &block)
        super(opts, &block)

        @index = Elastomer::Indexes::Gists.new
        @language = opts.fetch(:language, nil)
      end

      def global?
        filter_hash[:gist_id].global?
      end

      # Sets the list of source fields that will be returned for each matching
      # search document.
      #
      # value - Array of field names
      #
      def source_fields=(value)
        case value
        when Array, String
          @source_fields = Array(value) << "public"
          @source_fields.uniq!
        when nil, false
          @source_fields = %w[public]
        else
          @source_fields = true
        end
      end

      # Internal: Returns the Array of advanced search qualifiers supported by
      # this query type.
      def qualifier_fields
        self.class.field_list
      end

      # Internal: Returns the Array of fields that support aggregation queries.
      def aggregation_fields
        ["code.language_id"]
      end

      # Internal: Returns a Hash that will be passed as URL params for the query.
      def query_params
        { type: "gist" }
      end

      # Internal: Returns the Array of field names that will be queried.
      def query_fields
        return @query_fields if defined? @query_fields
        @query_fields = []

        search_in.each do |field|
          case field
          when "filename";        @query_fields << "code.filename^0.1"
          when "file";        @query_fields << "code.file"
          when "description"; @query_fields << "description"
          end
        end

        @query_fields = %w[code.filename^0.1 code.file description] if @query_fields.empty?
        @query_fields
      end

      # Internal: Constructs the actual `:query` portion of the query
      # document. This will later be wrapped in a filtered query if search
      # qualifiers were also used.
      #
      # Returns the search query Hash.
      def query_doc
        return @query_doc if defined? @query_doc

        qs = query_string_query
        bool = filename_query

        if qs && bool
          if bool[:must]
            bool[:must] = [qs, bool[:must]].flatten
          else
            bool[:must] = qs
          end
          @query_doc = { bool: bool }
        elsif qs
          @query_doc = qs
        elsif bool
          @query_doc = { bool: bool }
        end

        @query_doc
      end

      # Construct a query string type query using the query phrased typed in by
      # the user.
      #
      # Returns nil or a query string hash.
      def query_string_query
        return if escaped_query.empty?

        qs = {
          query: escaped_query,
          fields: query_fields,
          default_operator: "AND",
        }
        qs[:analyzer] = (strict? ? "code" : "code_search") if query_fields.include? "code.file"

        { query_string: qs }
      end

      # Determine how we need to analyze the query. If it contains un-escaped
      # quote characters, then we need to perform a stricter analysis; this
      # will analyze the query in the same way that the source code files were
      # analyzed. If the query does not contain quotes, then we can be a
      # little looser in how we analyze the tokens.
      #
      # Returns true if the query contains quoted text.
      def strict?
        query =~ /(^|[^\\])"/
      end

      # Internal: Returns the sorting options Array.
      def build_sort
        return if sort.blank?

        build_sort_section(sort, "_score", SORT_MAPPINGS)
      end

      # Returns the default sort ordering to use in the absence of a query or
      # any other sort information.
      def default_sort
        DEFAULT_SORT
      end

      def gist_filter
        filter_hash[:gist_id]
      end

      # Internal: We need to use the same filters for the query and for the
      # aggregations with the exception of the language query. Since we are aggregationing
      # on language, applying a language filter would be most unhelpful.
      #
      # Returns the Hash of filter hashes.
      def filter_hash
        return @filter_hash if defined? @filter_hash

        # override the language if created with a language option
        unless @language.nil?
          qualifiers[:language].clear
          qualifiers[:language].must @language
        end

        # the fork filter is a special case
        # by default we will not show forks in the search results - you have
        # to explicitly add "fork:true" or "fork:only" to the search
        qualifiers[:fork].must(false) unless qualifiers[:fork].must?

        # Don't show anon gists by default
        qualifiers[:anon].must(false) unless qualifiers[:anon].must?

        filters = {}

        filters[:forks]       = builder.range_filter(:forks)
        filters[:stars]       = builder.range_filter(:stars)
        filters[:created_at]  = builder.date_range_filter(:created_at, :created)
        filters[:updated_at]  = builder.date_range_filter(:updated_at, :updated)

        filters[:language_id] = builder.language_filter("code.language_id", :language_id, :language)
        filters[:extension]   = builder.term_filter("code.extension", :extension) { |str| str.downcase.sub(/^\./, "") }
        filters[:file_size]   = builder.range_filter("code.file_size", :size)

        filters[:gist_id]     = builder.gist_filter(current_user)

        filters[:fork]        = builder.term_filter(:fork, singular: true) do |value|
          case value
          when /true/i; nil
          when /only/i; true
          else false
          end
        end

        filters[:owner_id] = builder.term_filter(:owner_id, :anon, singular: true) do |value|
          case value.to_s.downcase
          when "t", "true" then nil
          when "only", "force" then :missing
          else :exists
          end
        end

        filters.delete_if { |_name, filter| filter.nil? || (filter.valid? && filter.blank?) }

        @filter_hash = filters
      end

      # Construct a match query for the filename and wrapper it inside a
      # boolean query. This should be combined with the query string parsed
      # from the users query phrase.
      #
      # Returns nil or a boolean query hash.
      def filename_query
        return unless qualifiers.key? :filename

        bool = {}
        fq = qualifiers[:filename]

        if fq.must?
          if fq.must.length == 1
            bool[:must] = { match: { "code.filename": fq.must.first } }
          else
            bool[:should] = fq.must.map { |filename| { match: { "code.filename": filename } } }
            bool[:minimum_should_match] = 1
          end
        end

        if fq.must_not?
          if fq.must_not.length == 1
            bool[:must_not] = { match: { "code.filename": fq.must_not.first } }
          else
            bool[:must_not] = fq.must_not.map { |filename| { match: { "code.filename": filename } } }
          end
        end

        bool
      end

      def valid_query?
        return false unless super

        if escaped_query.empty? && filter_hash.empty?
          @invalid_reason = ::Search::Query::REASON_EMPTY_QUERY
          return false
        end

        true
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

      # Internal: Take the array of repository results and remove those that
      # no longer exist in the database or have been flagged as spammy. We
      # will only perform this pruning in test and production; development
      # mode is for testing out everything.
      #
      # results - An Array of hits from the search index.
      #
      # Returns the pruned Array of hits.
      def prune_results(results)
        gist_ids = results.map { |h| h["_id"] }
        gists = Gist.where(id: gist_ids).index_by(&:id)

        results.delete_if do |h|
          gist_id = h["_id"].to_i
          gist = gists[gist_id]

          if gist.nil?
            RemoveFromSearchIndexJob.perform_later("gist", gist_id)
            true

          elsif !gist.gist_is_searchable?
            RemoveFromSearchIndexJob.perform_later("gist", gist_id)
            true

          else
            h["_gist"] = gist
            h["_model"] = gist
            !security_validation h

          end
        end
      end

      # Validate that the user is allowed to see the given search result
      # document.
      #
      # doc - The search result Hash
      #
      # Returns a boolean indicating visibility.
      def security_validation(doc)
        gist = doc["_gist"]

        return true if gist.public?

        @include_gists ||= gist_filter.accessible_gist_ids
        return true if @include_gists.include? gist.id

        GitHub.dogstats.increment("search.query.errors.security", { tags: ["index:" + index.name.to_s] })
        false
      end

    end  # GistQuery
  end  # Queries
end  # Search
