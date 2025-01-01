# typed: true
# frozen_string_literal: true

module Search
  module Queries

    class CodeQuery < ::Search::Query
      include Scientist

      # The set of fields that can be queried when performing a code search
      def self.field_list
        [:in, :sort, :language, :path, :filename, :fork, :size, :extension, :user, :org, :repo].freeze
      end

      # These tags are used to mark highlighted code snippets. We will swap them
      # out in the controller / view layers with some real HTML tags. They are
      # used to enable line numbering and syntax highlighting of the code snippets.
      PRE_TAG  = ::Search::OffsetHighlighter::PRE_TAG
      POST_TAG = ::Search::OffsetHighlighter::POST_TAG

      # The mapping of user-facing sort values to the corresponding values used
      # in the search index.
      SORT_MAPPINGS = {
        "indexed" => "indexed",
      }.freeze

      # Construct a CodeQuery. The query can be restricted to a single
      # language by providing a :language option. The query can also be
      # restricted to a single repository by providing the :repo_id option.
      #
      # opts - The options Hash.
      #   :language - The language name or Linguist::Language instance to filter by
      #   :repo_id  - The Repository ID to filter by
      #
      def initialize(opts = {}, &block)
        super(opts, &block)

        @index            = Elastomer::Indexes::CodeSearch.new
        @language         = opts.fetch(:language, nil)
        @repo_id          = opts.fetch(:repo_id, nil)
        @request_category = opts.fetch(:request_category, nil)
      end

      def global?
        repository_filter.global?
      end

      # Sets the list of source fields that will be returned for each matching
      # search document.
      #
      # value - Array of field names
      #
      def source_fields=(value)
        case value
        when Array, String
          @source_fields = Array(value).concat(%w[repo_id public])
          @source_fields.uniq!
        when nil, false
          @source_fields = %w[repo_id public]
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
        [:language_id]
      end

      # Internal: Returns a Hash that will be passed as URL params for the query.
      def query_params
        h = { type: "code" }
        h[:routing] = routing if routing.present?
        h
      end

      # Internal: Determine the query context. This will result in one of eight
      # possible strings
      #
      #   "api.global",        "api.scoped"
      #   "enterprise.global", "enterprise.scoped"
      #   "web.global",        "web.scoped"
      #   "raw.global",        "raw.scoped"
      #
      # Search requests from the API are tagged with "api". Search requests from
      # the web UI are tagged with "web". If the query class is used outside the
      # scope of a Rack request then search requests are tagged with "raw".
      #
      # These context strings are used when creating metric names for recording
      # query timing information. See `config/instrumentation/search.rb`
      def context
        request_category =
          if self.current_enterprise_installation
            "enterprise"
          elsif @request_category
            @request_category
          else
            "raw"
          end

        scope = global? ? "global" : "scoped"

        "#{request_category}.#{scope}"
      end

      # Returns true if code search is currently enabled.
      def enabled?
        return @enabled if defined? @enabled
        @enabled = super && (ClusterStatus.code_search_enabled? || @current_user&.site_admin?)
      end

      # Internal: Returns the Array of field names that will be queried.
      def query_fields
        return @query_fields if defined? @query_fields
        @query_fields = []

        search_in.each do |field|
          case field
          when "file"; @query_fields << "file"
          when "path"; @query_fields << "path^0.1" << "filename^0.1"
          end
        end

        @query_fields = %w[file] if @query_fields.empty?
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
        qs[:analyzer] = (strict? ? "code" : "code_search") if query_fields.include? "file"
        { query_string: qs }
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
            bool[:must] = match_filename(fq.must.first)
          else
            bool[:should] = fq.must.map { |filename| match_filename(filename) }
            bool[:minimum_should_match] = 1
          end
        end

        if fq.must_not?
          if fq.must_not.length == 1
            bool[:must_not] = match_filename(fq.must_not.first)
          else
            bool[:must_not] = fq.must_not.map { |filename| match_filename(filename) }
          end
        end

        bool
      end

      # Internal: Generates a `match` query for the given filename.
      #
      # filename - the filename to match
      #
      # Returns a `match` query
      def match_filename(filename)
        { match: { filename: {
          query: filename,
          operator: "and",
        } } }
      end

      # Determine how we need to analyze the query. If it contains un-escaped
      # quote characters, then we need to perform a stricter analysis; this
      # will analyze the query in the same way that the source code files were
      # analyzed. If the query does not contain quotes, then we can be a
      # little looser in how we analyze the tokens.
      #
      # Returns true if the query contains quoted text.
      def strict?
        (query =~ /\s/ && query =~ /(^|[^\\])"/) ? true : false
      end

      # Internal: Returns the highlight Hash.
      def build_highlight
        fields = {}

        if query_fields.any? { |str| str =~ /^path\b/ }
          fields[:path] = {
            number_of_fragments: 0,  # force the whole path to be included in the fragment
          }
          fields[:filename] = {
            number_of_fragments: 0,  # force the whole filename to be included in the fragment
          }
        end

        if qualifiers.key? :filename
          fields[:filename] = {
            number_of_fragments: 0,  # force the whole filename to be included in the fragment
          }
        end

        if query_fields.any? { |str| str =~ /^file\b/ }
          fields[:file] = {
            number_of_fragments: 2,
            # :fragment_size => 160,
            # :boundary_chars => "\r\n",
            # :boundary_max_size => 80
          }
        end

        unless fields.empty?
          { type: "plain",
            encoder: "default",
            pre_tags: [PRE_TAG],
            post_tags: [POST_TAG],
            fields: fields,
            require_field_match: true,
          }
        end
      end

      # Internal: Returns the sorting options Array.
      def build_sort
        return if sort.blank?

        map = { "indexed" => "timestamp" }
        build_sort_section(sort, "_score", map)
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

        # Don't return commit state documents in the search results
        qualifiers[:is_code_search_state_doc].must_not(true)

        filters = {}

        filters[:language_id] = builder.language_filter(:language_id, :language_id, :language)
        filters[:extension]  = builder.term_filter(:extension) { |str| str.downcase.sub(/^\./, "") }
        filters[:file_size]  = builder.range_filter(:file_size, :size)
        filters[:repo_id]    = builder.repository_filter(current_user, @repo_id, nil, user_session: user_session, ip: remote_ip)
        filters[:is_code_search_state_doc] = builder.term_filter(:is_code_search_state_doc)

        filters[:fork] = builder.term_filter(:fork, singular: true) do |value|
          case value
          when /\Atrue\z/i; nil
          when /\Aonly\z/i; true
          else false
          end
        end

        filters[:path] = builder.term_filter("path.filter", :path) do |str|
          str = str.downcase.strip.sub(/^\/+/, "").sub(/\/+$/, "")
          str.empty? ? :missing : str
        end

        filters.delete_if { |_name, filter| filter.nil? || (filter.valid? && filter.blank?) }

        @filter_hash = filters
      end

      # Internal: Take the repository IDs and generate a routing String. This
      # routing string is used to limit our search to the specific set of
      # shards where the repository source code is stored.
      #
      # Returns a routing String.
      def routing
        return @routing if defined? @routing
        @routing = @repo_id

        if @repo_id.nil? && !repository_filter.global?
          ids = repository_filter.accessible_repository_ids
          @routing = ids.to_a.join(",") unless ids.length > 200
        end

        @routing
      end

      def repository_filter
        filter_hash[:repo_id]
      end

      def valid_query?
        if !GitHub.enterprise?
          if current_user && current_user.codesearch_disabled?
            @invalid_reason = "Code search is not available at this time."
            return false
          end

          if !current_user && !current_enterprise_installation && global?
            @invalid_reason = "Must include at least one user, organization, or repository"
            return false
          end
        end

        if escaped_query.length > 128
          @invalid_reason = "The search is longer than 128 characters."
          return false
        end

        return false unless super

        if global? && query_doc.blank?
          filters = filter_hash.keys - [:repo_id]
          @invalid_reason = if filters.empty?
            ::Search::Query::REASON_EMPTY_QUERY
          else
            "Search text is required when searching source code. Searches that use qualifiers only are not allowed. Were you searching for something else?"
          end
          return false
        elsif query_doc.blank?
          filters = filter_hash.keys - [:repo_id]
          if filters.empty?
            @invalid_reason = "Search text is required when searching source code. Searches that use qualifiers only are not allowed. Were you searching for something else?"
            return false
          end
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

      # Internal: Take the array of code results and remove those for which
      # the repository no longer exists or has been flagged as spammy. We will
      # only perform this pruning in test and production; development mode is
      # for testing out everything.
      #
      # results - An Array of hits from the search index.
      #
      # Returns the pruned Array of hits.
      #
      def prune_results(results)
        repo_ids = Set.new
        results.each { |h| repo_ids << h["_source"]["repo_id"] }
        repos = Repository.where(id: repo_ids.to_a.flatten.compact).index_by(&:id)

        repo_repairs = {}

        results.delete_if do |h|
          repo_id = h["_source"]["repo_id"].to_i
          repo = repos[repo_id]

          if repo.nil? && !Rails.env.development?
            RemoveFromSearchIndexJob.perform_later("code", repo_id) if GitHub.use_elastomer_code_search?
            RemoveFromSearchIndexJob.perform_later("repository", repo_id)
            true
          elsif !repo.code_is_searchable? && !Rails.env.development?
            RemoveFromSearchIndexJob.perform_later("code", repo_id) if GitHub.use_elastomer_code_search?
            true
          elsif repo.public != h["_source"]["public"]
            unless repo_repairs[repo_id]
              Search.add_to_search_index("code", repo_id, "purge" => true)
              GitHub.dogstats.increment("search.reconcile.update", tags: datadog_tags)
              repo_repairs[repo_id] = true
            end
            true
          else
            h["_model"] = repo
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
        repo = doc["_model"]

        return true if repo.public?

        @include_repos ||= repository_filter.accessible_repository_ids
        return true if @include_repos.include? repo.id

        GitHub.dogstats.increment("search.query.errors.security", tags: datadog_tags)
        false
      end
    end  # CodeQuery
  end  # Queries
end  # Search
