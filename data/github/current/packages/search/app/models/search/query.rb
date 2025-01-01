# typed: true
# frozen_string_literal: true

module Search
  # The Query class contains all the basic functionality for constructing
  # specific query types. It should not be used directly; instead it should be
  # subclasses and the various build_* methods overridden to generate the
  # desired ElasticSearch query document.
  #
  class Query
    # Standard number of results to return.
    sig { overridable.returns(Integer) }
    def self.per_page_default
      10
    end

    # The maximum item that can be accessed through pagination (from + size)
    #
    # It checks not only the offset but also the final item in the resultset.
    # This value is per index and defaults to 10k in ElasticSearch.
    # ElasticSearch raises IllegalArgument "Result window is too large".
    sig { overridable.returns(Integer) }
    def self.max_offset_window_default
      10_000
    end

    # The maximum allowed offset into the search results.
    #
    # The total number of search results that will ever be returned is
    # capped. The farther you offset into a set of search results, the more
    # work the search index has to do. This adversely affects performance;
    # hence it is capped. /deal with it
    # This limits the starts of the range, but it may also be capped further by MAX_RESULT_WINDOW
    # which checks the end of the range. I.e. a max_offset of 10_000 would allow the page 334,
    # but it would include results above 10_000 so MAX_RESULT_WINDOW caps further the max page to 333.
    sig { overridable.returns(Integer) }
    def self.max_offset_default
      1000
    end

    # Raised when the self.max_offset_default is exceeded
    MaxOffsetError = Class.new(StandardError)

    # Not raised directly but used to log query rejections
    QueryRejectionError = Class.new(StandardError)

    # The set of fields that can be queried when performing a search
    sig { overridable.returns(T::Array[Symbol]) }
    def self.field_list
      []
    end

    # A set of terms that have mutually exclusive values.
    sig { overridable.returns(T::Array[Symbol]) }
    def self.unique_field_list
      []
    end

    # the set of terms that support @me
    USERNAME_SEARCH_FIELDS = %i{
      user
      author
      assignee
      mentions
      commenter
      involves
      reviewed-by
      review-requested
      user-review-requested
    }.freeze

    COPILOT_SEARCH_FIELDS = %i{
      reviewed-by
      review-requested
      assignee
      author
      involves
    }.freeze

    COPILOT_SEARCH_FIELD_TO_APP_ALIAS = {
      "reviewed-by": [:copilot_pull_request_reviewer],
      "review-requested": [:copilot_pull_request_reviewer],
      "assignee": [:copilot_swe_agent],
      "author": [:copilot_swe_agent],
      "involves": [:copilot_swe_agent, :copilot_pull_request_reviewer],
    }.freeze

    MACRO_ME = "@me".freeze
    MACRO_TODAY = "@today".freeze
    MACRO_COPILOT = "@copilot".freeze

    # An Array of fields that support the memex-style enumeration
    # syntax. Currently only used for `:label` in issue search
    # This is a method rather than a constant to enable easier feature
    # flagging.
    def self.enumerable_terms(current_user:)
      # The base class method requires a current_user argument but does nothing with it.
      # Subclasses can use the argument for feature flagging.
      []
    end

    # Public: Parse search query syntax.
    #
    # phrase - The String phrase
    #
    # Examples
    #
    #     parse("parser label:search author:TwP", [:label, :author])
    #     # => ["parser", [:label, "search"], [:author, "TwP"]]
    #
    # Returns an Array of components where a component is a literal String
    # query or an Array of [Symbol key, String value, Boolean negative].
    def self.parse(phrase, current_user = nil)
      fields = self.field_list
      ParsedQuery.parse(phrase, terms: fields, viewer: current_user, enumerable_terms: enumerable_terms(current_user: current_user))
    end

    # Public: coerce the object into an array of search components via `parse`
    def self.coerce(query_object, current_user = nil)
      return query_object if query_object.is_a?(Array)
      fields = self.field_list
      return ParsedQuery.parse(query_object, terms: fields, viewer: current_user, enumerable_terms: enumerable_terms(current_user: current_user)) if query_object.is_a?(String)
      raise ArgumentError, "query must be an Array or String, not #{query_object.class}"
    end

    # Public: Determines if this is the default query on Issues#Index page
    # Being either a search for only open issues, or open pulls.
    def self.is_default_issues_index_query?(parsed_query_object)
      return false unless parsed_query_object.is_a?(Array)
      return false unless parsed_query_object.length == 2
      is_issue_search = parsed_query_object.include?([:is, "issue"])
      is_pr_search = parsed_query_object.include?([:is, "pr"])

      parsed_query_object.include?([:is, "open"]) && (is_issue_search || is_pr_search)
    end

    # Internal: Normalize terms in parsed query.
    #
    # Removes duplicate terms prefering the right most term.
    #
    # ary - Parsed query Array
    #
    # Returns Array.
    def self.normalize(ary)
      uniq_fields = self.unique_field_list

      seen = Set.new
      ParsedQuery.filter_terms(ary) do |key, value|
        # no:milestone, no:assignee
        key = value.to_sym if key == :no
        key = key.to_s[1, key.length - 1].to_sym if key.to_s.start_with?("-") # treat negated terms the same as non-negated

        if uniq_fields.include?(key) && seen.include?(key)
          false
        else
          seen.add(key)
          true
        end
      end
    end

    # Public: Generate a normalized Issue search query String given a parsed
    # query Array.
    #
    # ary - Parsed query Array
    #
    # Examples
    #
    #     stringify(["parser", [:label, "search"], [:author, "TwP"]])
    #     # => "parser label:search author:TwP"
    #
    # Returns a search query String.
    def self.stringify(ary)
      ParsedQuery.stringify(normalize(ary))
    end

    # Public: Helper method that will convert a `page` and `per_page` value into
    # an Elasticsearch query offset.
    #
    # page     - The 1-based page number
    # per_page - The number of results per page
    #
    # Returns an `offset` value.
    def self.to_offset(page:, per_page: self.per_page_default)
      page = page.to_i
      page = 1 if page < 1

      per_page = per_page.to_i
      per_page = self.per_page_default if per_page < 1

      (page - 1) * per_page
    end

    # Public: Helper method that will convert the @copilot macro
    # into corresponding slug/slugs.
    #
    # qualifier_term     - a COPILOT_SEARCH_FIELDS symbol
    #
    # Returns the slugs with [bot] suffix or nil
    sig { params(qualifier_term: Symbol).returns(T.nilable(T.any(String, T::Array[String]))) }
    def self.copilot_macro_to_slugs(qualifier_term)
      eligible_copilot_app_aliases = COPILOT_SEARCH_FIELD_TO_APP_ALIAS[qualifier_term]

      return nil if eligible_copilot_app_aliases.nil?

      slugs = eligible_copilot_app_aliases.map do |app_alias|
        if app = Apps::Privileged.integration(app_alias)
          "#{Apps::Privileged.property(:searchable_slug, app: app)}#{Bot::LOGIN_SUFFIX}"
        end
      end.compact

      return nil if slugs.empty?

      if slugs.length == 1 || GitHub.flipper[:copilot_involves_filter_kill_switch].enabled?
        slugs.first
      else
        slugs
      end
    end

    # Create a Query to execute against the ElasticSearch indexes.
    #
    def initialize(opts = {})
      self.current_user  = opts.fetch(:current_user, nil)
      @quote_words       = opts.fetch(:quote_words, true)
      self.query         = opts.fetch(:query, nil)
      self.qualifiers    = opts.fetch(:qualifiers, nil)
      self.current_installation = opts.fetch(:current_installation, nil)
      self.current_enterprise_installation = opts.fetch(:current_enterprise_installation, nil)
      self.user_session  = opts.fetch(:user_session, nil)
      self.remote_ip     = opts.fetch(:remote_ip, nil)
      self.highlight     = opts.fetch(:highlight, false)
      self.normalizer    = opts.fetch(:normalizer, nil)
      self.dotcom_normalizer = opts.fetch(:dotcom_normalizer, nil)
      self.catalog_service = opts.fetch(:catalog_service, nil)

      self.source_fields = opts.fetch(:source_fields, true)
      self.aggregations  = opts.fetch(:aggregations, false)
      self.sort          = opts.fetch(:sort, nil)
      self.max_offset    = opts.fetch(:max_offset, self.class.max_offset_default)
      self.max_offset_window = opts.fetch(:max_offset_window, self.class.max_offset_window_default)

      # T.must asserts that this will not be a nameless anonymous class, which would throw an exception here.
      self.context                = opts.fetch(:context, T.must(self.class.name).demodulize.underscore)
      self.originating_request_id = opts.fetch(:originating_request_id, "")

      @per_page = opts.fetch(:per_page, self.class.per_page_default)
      configure_page_and_offset(opts)

      # Set preference to _local if Enterprise to allow queries to succeed
      # on HA pairs when the replica is offline.
      if GitHub.enterprise?
        self.preference = :_local
      end

      @raw_phrase = opts[:raw_phrase]
      self.phrase = opts[:phrase] if opts.key? :phrase

      yield self if block_given?
    end

    # The Elastomer::Index instance used when querying ElasticSearch.
    attr_reader :index

    # The search phrase straight from the user. No parsing has been performed
    # on this String.
    attr_reader :phrase
    attr_reader :raw_phrase

    # The query terms parsed from the search phrase.
    attr_reader :query

    attr_reader :escaped_query

    # The Hash of qualifier terms parsed from the search phrase.
    attr_reader :qualifiers

    # The currently logged in User (can be nil).
    attr_accessor :current_user

    # The currently authenticated IntegrationInstallation (can be nil).
    attr_accessor :current_installation

    # The UserSession for the currently logged in User (can be nil).
    attr_accessor :user_session

    # The currently authenticated EnterpriseInstallation (can be nil).
    attr_accessor :current_enterprise_installation

    # Query context tag for annotating query metrics sent to DataDog.
    attr_accessor :context

    # An explicit catalog service value.  If not present, will default to GitHub.context[:catalog_service]
    attr_accessor :catalog_service

    # Either a boolean flag or default highlighting options. If default
    # options are provided the we assume that highlighting is enabled.
    attr_reader :highlight

    # Current request ID, or if the query was triggered as an async
    # dark-ship query by another query, this is _that_ query's original
    # request ID. Helps to join both in the data warehouse for comparison
    attr_accessor :originating_request_id

    # Set the default highlighting options or simply enable or disable
    # highlighting altogether. Providing default options implies that
    # highlighting of search results will be enabled.
    #
    # value - true, false, or a default options Hash
    #
    # Returns the value.
    def highlight=(value)
      @highlight =
          case value
          when true, false, Hash; value
          else false
          end
    end

    # Returns true if highlighting is requested for the search results.
    def highlight?
      highlight == false ? false : true
    end

    # The Array of document source fields to return in the search results.
    attr_accessor :source_fields

    # The aggregations to generate with the query.
    attr_reader :aggregations

    # Set the desired aggregations for the query. When set to `false` no aggregations will
    # be generated for the query. When set to `true` all aggregations will be
    # generated. Or you can pass in one or more Symbols specifying the aggregations
    # to use.
    #
    # value - true, false, a Symbol, or an Array of Symbols
    #
    # Returns the value.
    def aggregations=(value)
      @aggregations =
          case value
          when true; aggregation_fields
          when Array, Symbol; Array(value)
          else false
          end
    end

    # Returns true if aggregations have been defined for the query.
    def aggregations?
      aggregations.present?
    end

    # A tuple containing the field to sort on and the sort order.
    attr_writer :sort

    # The sort order of the search results can be specified by setting the
    # `sort` value. There are two ways to set the sort order: either directly
    # in Ruby code by `query.sort = ['field', 'desc']`, or by passing in the
    # sort order as part of the query phrase.
    #
    # This method will return the sort value if set, or it will look for the
    # `sort:field-order` string from the query phrase. If neither are set then
    # this method returns nil.
    #
    # Examples
    #
    #   # :phrase => 'foo sort:updated'
    #   sort  #=> ['updated', 'desc']
    #
    #   # :phrase => 'foo sort:updated-asc'
    #   sort  #=> ['updated', 'asc']
    #
    #   # :phrase => 'foo sort:comments,updated-asc'       OR
    #   # :phrase => 'foo sort:comments sort:updated-asc'
    #   sort  #=> ['comments', 'desc', 'updated', 'asc']
    #
    # Returns a tuple containing the field to sort on and the sort order.
    def sort
      return @sort if defined?(@sort) && !@sort.nil?

      sort = qualifiers.delete :sort

      ary = sort.nil? ? [] : Array(sort.must)
      ary.map! { |str| str.split(/[,\s]/) }
      ary.flatten!

      if ary.empty?
        @sort = default_sort if query.empty? || '""' == query
      else
        ary.map! do |str|
          matches = /\A(.+?)(?:-(asc|desc))?\z/i.match(str.downcase)
          next nil unless matches
          [matches[1], matches[2] || "desc"]
        end
        ary.flatten!
        ary.compact!

        @sort = ary
      end
    end

    # Returns nil by default
    def default_sort
      nil
    end

    # The search results page to return.
    attr_reader :page

    # The number of documents to return per page of results.
    attr_accessor :per_page

    # The maximum allowed offset into the search results
    attr_accessor :max_offset

    # The maximum allowed result that can be accessed through pagination (from + size)
    attr_accessor :max_offset_window

    # Set shard preference. See allowed values here:
    # http://www.elasticsearch.org/guide/en/elasticsearch/reference/current/search-request-preference.html
    # On Enterprise, we set this to _local to increase availability of HA
    # primary/replica pairs.
    attr_writer :preference

    # Returns the shard preference to use when performing this query. The
    # preference ensures that results maintain a fixed order when paginating
    # through a result set.
    #
    # If the query has a current user, then that user ID is used as the
    # preference string. If a remote IP address has been given then that is used
    # as the preference string. The preference can also be set to one of the
    # special values here: https://www.elastic.co/guide/en/elasticsearch/reference/current/search-request-preference.html
    #
    # Returns a String or `nil`.
    def preference
      return @preference if defined? @preference
      @preference = current_user && current_user.id || remote_ip
      @preference = @preference.to_s unless @preference.nil?
      @preference
    end

    # The remote IP address for the associated search request
    attr_accessor :remote_ip

    # The normalizer function to be applied to the search results.
    attr_accessor :normalizer

    # The normalizer function to be applied to the search results.
    attr_accessor :dotcom_normalizer

    # Set the search phrase to the value. If the value is blank, this will
    # reset the search phrase and any parsed values to nil. Otherwise, the
    # search phrase will be parsed and the query and qualifier terms will be
    # set from the parsed results.
    def phrase=(value)
      @phrase = value.to_s

      if @phrase.empty?
        self.query = nil
        self.qualifiers = nil
      else
        pq = Search::ParsedQuery.new(@phrase, qualifier_fields, current_user, self.class.enumerable_terms(current_user: current_user))
        self.query = pq.query
        self.qualifiers = pq.qualifiers
      end
    end

    # Set the query to the value given. If the query contains unmatched quote
    # `"` characters, the last unmatched quote will be removed. Unmatched
    # quotes cause all kinds of headaches for the Lucene query parser.
    #
    # Examples
    #
    #   self.query = "this is an \"unmatched quote"
    #   self.query
    #   #=> "this is an unmatched quote"
    #
    #   self.query = "this is an \\\"escaped quote"
    #   self.query
    #   #=> "this is an \\\"escaped quote" )
    #
    def query=(value)
      @query = value.to_s.strip

      if @query =~ /^"+$/
        @query = ""
      else
        quote_count = @query.scan(/(?=^"|[^\\]")/).length
        @query.sub!(/(^|[^\\])"(?!.*[^\\]")/, '\1') if quote_count.odd?
      end

      @query = quote_words(@query) if @quote_words

      self.escaped_query = @query
    end

    #
    #
    def escaped_query=(value)
      q = Search.escape_characters(value).tr("<>", " ")
      @escaped_query = (q =~ /^["\s\\]*$/ ? "" : q)
    end

    # Set the qualifiers to the given value. If the value is nil, then an
    # empty Hash is used. Otherwise we create a copy of the qualifiers Hash.
    #
    # value - The qualifiers as a Hash
    #
    def qualifiers=(value)
      @qualifiers = value.nil? ? ::Search::ParsedQuery.qualifiers : value

      # Apply @me macros
      if current_user
        me_macro_applied = T.let(false, T::Boolean)
        USERNAME_SEARCH_FIELDS.each do |term|
          next unless @qualifiers.has_key? term
          @qualifiers[term].map_all! do |value|
            if Search::Query::MACRO_ME.casecmp?(value)
              me_macro_applied = true
              current_user.display_login
            else
              value
            end
          end
        end
        GitHub.dogstats.increment("search.me_macro") if me_macro_applied
      end

      copilot_macro_applied = T.let(false, T::Boolean)
      COPILOT_SEARCH_FIELDS.each do |term|
        next unless @qualifiers.has_key? term
        @qualifiers[term].map_all! do |value|
          if !Search::Query::MACRO_COPILOT.casecmp?(value)
            value
          else
            slugs = self.class.copilot_macro_to_slugs(term)
            if slugs.present?
              copilot_macro_applied = true
              next slugs
            end

            value
          end
        end
      end
      GitHub.dogstats.increment("search.copilot_macro") if copilot_macro_applied
    end

    # Calculates a cache key for this query's result set.
    #
    # Examples
    #
    #   cache_key
    #   #=> 'search/queries/code_query/<some_sha>'
    #
    # Returns a String identifying the query with its options.
    def cache_key
      sha = Digest::SHA256.new
      query_doc = query_document
      sha.update(query_doc.to_s)
      sha.update(query_params.to_s)
      # T.must ensures that the class name will not be nil (as it would be with an anonymous class)
      "#{T.must(self.class.name).underscore}:#{sha.hexdigest}:v#{search_content_cache_version}"
    end

    # Calculates a cache key for count queries.
    #
    # Examples
    #
    #   count_cache_key
    #   #=> 'search/queries/code_query/<some_sha>/count'
    #
    # Returns a String identifying the count query with its options.
    def count_cache_key
      sha = Digest::SHA256.new
      sha.update(count_document.to_s)
      sha.update(query_params.to_s)
      # T.must ensures that the class name will not be nil (as it would be with an anonymous class)
      "#{T.must(self.class.name).underscore}:#{sha.hexdigest}:v#{search_content_cache_version}:count"
    end

    # Calculates a cache key for count_with_timeout queries.
    #
    # Examples
    #
    #   count_with_timeout_cache_key
    #   #=> 'search/queries/code_query/<some_sha>/count_with_timeout'
    #
    # Returns a String identifying the count query with its options.
    def count_with_timeout_cache_key
      sha = Digest::SHA256.new
      sha.update(count_with_timeout_document.to_s)
      sha.update(query_params.to_s)
      # T.must ensures that the class name will not be nil (as it would be with an anonymous class)
      query_class = T.must(self.class.name).underscore
      if self.is_a?(Search::Queries::IssueQuery) && !@raw_phrase.nil? && (@raw_phrase.include?("is:pr") || @raw_phrase.include?("is:pull-request"))
        query_class = query_class.sub("issue", "pull_request")
      end
      "#{query_class}:#{sha.hexdigest}:v#{search_content_cache_version}:count_with_timeout"
    end

    # Internal: Version for the memcache'd version of search content.
    #
    # Returns the cache version
    def search_content_cache_version
      3
    end

    # Boolean flag used to enable or disable the query. When disabled the
    # execute method will not perform the query. Instead, the empty Results
    # object will be returned for all queries.
    #
    # Returns true when the Query is enabled.
    def enabled?
      true
    end

    # Perform the query against the ElasticSearch index and return the
    # results. The response from ElasticSearch is converted into a
    # Search::Results object. If the Query has been configured with a
    # `normalizer` then it will be run over the array of hits contained in the
    # Results.
    # if skip_prune_results true, do not prune results
    #
    # Returns a Search::Results object.
    sig do
      overridable
      .params(skip_prune_results: T::Boolean, results_class: T.class_of(Search::Results))
      .returns(Search::Results[T.untyped])
    end
    def execute(skip_prune_results: false, results_class: Search::Results)
      return results_class.empty unless enabled?
      unless valid_query?
        GitHub.dogstats.increment("search.query.reject", tags: datadog_tags)
        rejection = QueryRejectionError.new(@invalid_reason || "Reason Unknown")
        log_query(at: "execute", error: rejection)
        return results_class.empty
      end

      @results_pruned = false
      @results_total_count = nil

      results = T.let(nil, T.nilable(Search::Results[T.untyped]))
      GitHub.dogstats.increment("search.query.total", tags: datadog_tags)
      GitHub.dogstats.time("search.execute.time", tags: datadog_tags) do
        query = query_document
        # Keep track of whether highlighted results have been HTML escaped.
        highlight_html_encoder = query[:highlight] &&
                                 query[:highlight][:encoder] == :html
        params = build_query_params
        response = T.let(nil, T.nilable(T::Hash[T.untyped, T.untyped]))
        GitHub.dogstats.time("search.query.time", tags: datadog_tags) do
          response = index.search(query, **params)
        end

        options = { page:, per_page:, max_offset:, max_offset_window: }
        results = build_response(results_class, response, options)
        if !skip_prune_results
          results.results = prune_results(results.results) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        end

        @results_pruned = true
        @results_total_count = results.total
        instrument_execute(query, params, results)
        log_query(at: "execute", data_hash: execute_results_log_metadata(results))
        log_cache_key(:cache_key)

        results.results = set_highlights_html_safe(results.results) if highlight_html_encoder
        results.results = normalize(results.results)
      end

      GitHub.dogstats.increment("search.query.success", tags: datadog_tags)
      results
    rescue ElastomerClient::Client::RequestError, ElastomerClient::Client::ServerError, ElastomerClient::Client::TimeoutError => boom
      GitHub.dogstats.increment("search.query.errors", tags: datadog_tags(boom))
      log_query(at: "execute", error: boom)

      if tracked_exception?(boom)
        env = {
          "db.elasticsearch.path_parts.index": index.name,
          "db.elasticsearch.cluster.name": index.cluster_name,
          app: "github-user",
        }

        Failbot.report(boom, env)
      end

      results_class.empty(error_message: boom.message, error_details: error_to_hash(boom))
    end

    def execute_dotcom(current_user, type)
      headers = {}
      accept = %w(application/vnd.github.text-match+json application/vnd.github.extended-search-results+json)
      headers["Accept"] = accept.join(", ")
      if GitHub.dotcom_private_search_enabled?
        user_token = DotcomUser.for(current_user)&.token
      end

      response = GitHub::Connect.execute_dotcom_search(type, @raw_phrase, page, headers, user_token)
      return DotcomResults.timed_out if response.respond_to?(:error)
      return DotcomResults.empty if response["items"].empty?

      results = DotcomResults.new(response, page: page, per_page: per_page, max_offset: max_offset)

      results.results = dotcom_normalize(results.results)
      results
    end

    # Perform a count query against the ElasticSearch index and return the
    # number of matching documents.
    #
    # Returns the number of matching documents.
    def count
      return 0 unless enabled?
      return 0 unless valid_query?
      return @results_total_count unless @results_total_count.nil?

      log_query(at: "count")
      log_cache_key(:count_cache_key)

      params = build_query_params

      index.count(count_document, params.except(:timeout, :track_total_hits))
    rescue ElastomerClient::Client::RequestError, ElastomerClient::Client::ServerError, ElastomerClient::Client::TimeoutError => boom
      GitHub.dogstats.increment("search.count.query.errors", tags: datadog_tags(boom))
      log_query(at: "count", error: boom)

      if tracked_exception?(boom)
        env = {
          "db.elasticsearch.path_parts.index": index.name,
          "db.elasticsearch.cluster.name": index.cluster_name,
          app: "github-user",
        }
        Failbot.report(boom, env)
      end

      0
    end

    def count_with_timeout_total
      @results_total_count ||= count_with_timeout.total
    end

    # Perform a count query against the ElasticSearch index and return the
    # number of matching documents.
    #
    # Returns the number of matching documents.
    def count_with_timeout(results_class: Search::Results)
      return results_class.empty unless enabled?
      return results_class.empty unless valid_query?

      log_query(at: "count_with_timeout")
      log_cache_key(:count_with_timeout_cache_key)

      params = build_query_params

      response = index.count_with_timeout(count_with_timeout_document, params)
      build_response(results_class, response || {}, {})
    rescue ElastomerClient::Client::RequestError, ElastomerClient::Client::ServerError, ElastomerClient::Client::TimeoutError => boom
      GitHub.dogstats.increment("search.count.query.errors", tags: datadog_tags(boom))
      log_query(at: "count_with_timeout", error: boom)
      if tracked_exception?(boom)
        Failbot.report boom
      end
      results_class.empty(error_message: boom.message, error_details: error_to_hash(boom))
    end

    # Internal: Returns the Array of qualifier terms that should be parsed
    # from the search phrase. This method should be overridden by subclasses
    # to specify the qualifiers compatible with the Query.
    def qualifier_fields
      self.class.field_list
    end

    # Internal: Returns the Array of fields that support aggregation queries. This
    # method should be overridden by subclasses to specify the aggregation fields
    # compatible with the Query.
    def aggregation_fields
      []
    end

    # Internal: Returns the Integer offset into the search results
    # corresponding to the current page.
    #
    # If `offset` is set, then that is used, otherwise offset is calculated from `page`/`per_page`
    def offset
      if @offset >= max_offset
        Failbot.push(app: "github-user")
        GitHub.dogstats.increment("search.query.offset_limit", tags: datadog_tags)
        raise MaxOffsetError, "Only the first #{max_offset} search results are available"
      end

      if @offset + per_page > max_offset_window
        Failbot.push(app: "github-user")
        GitHub.dogstats.increment("search.query.max_result_window", tags: datadog_tags)
        raise MaxOffsetError, "The requested page includes results above the #{max_offset_window} limit"
      end

      @offset
    end

    # Internal: Configures the :page and :offset from the given options hash.
    # Only one value can be given otherwise an ArgumentError will be raised.
    #
    # opts - Options Hash
    #   :page   - One based page number
    #   :offset - Zero based offset into the search results
    #
    # Returns this Query instance.
    # Raises ArgumentError
    def configure_page_and_offset(opts)
      if page = opts.fetch(:page, nil)
        raise ArgumentError, "Use :offset or :page, not both." if opts.has_key?(:offset)

        page = page.to_i
        page = 1 if page < 1

        @page = page
        @offset = Search::Query.to_offset(page: page, per_page: per_page)
      else
        offset = opts.fetch(:offset, 0).to_i
        offset = 0 if offset < 1

        @page = nil
        @offset = offset
      end

      self
    end

    # Internal: No-op pruning method for the base query class to allow pruning
    # and normalizing results seperately in the execute method. Specific query
    # classes should implement this method to handle pruning specific to their
    # results.
    #
    # results - An Array of hits from the search index.
    #
    # Returns the Array of hits.
    #
    def prune_results(results)
      results
    end

    # Internal: If a `normalizer` has been given, then it will be called and
    # the Array of results will be passed to it. This normalizer is
    # responsible for transforming the hit Hashes contained in the results
    # into the format desired by the caller.
    #
    # If the Query does not have a `normalizer`, then the results array is
    # returned unchanged.
    #
    # results - An Array of hits from the search index.
    #
    # Returns the output of the `normalizer` or the input Array.
    def normalize(results)
      if normalizer.respond_to? :call
        normalizer.call results
      else
        results
      end
    end

    # Internal: If a `dotcom_normalizer` has been given, then it will be called and
    # the Array of results will be passed to it. This normalizer is
    # responsible for transforming the hit Hashes contained in the results
    # into the format desired by the caller.
    #
    # If the Query does not have a `normalizer`, then the results array is
    # returned unchanged.
    #
    # results - An Array of hits from the dotcom api.
    #
    # Returns the output of the `dotcom_normalizer` or the input Array.
    def dotcom_normalize(results)
      if dotcom_normalizer.respond_to? :call
        dotcom_normalizer.call results
      else
        results
      end
    end

    # Internal: Sets the highlighted search results of a Query as `html_safe`.
    # This method assumes a query highlight configuration that HTML escapes the
    # highlight search results(`:encoder => :html`) so that highlights can be
    # used in a template safely.
    #
    # results - An Array of hits from the search index.
    #
    # Returns an Array with highlight results marked `html_safe`
    def set_highlights_html_safe(results)
      results.map do |result|
        next result unless result["highlight"]
        result["highlight"].each do |_field, highlight_results|
          highlight_results.map! do |highlight_result|
            highlight_result.html_safe # rubocop:disable Rails/OutputSafety
          end
        end
        result
      end
    end

    # Internal: Merge the default query params and the class-defined query params.
    #
    # Returns a Hash that will be passed as the URL params for the query.
    def build_query_params
      return @build_query_params if defined? @build_query_params

      params = query_params
      params[:context] = context

      if index.index_running_version_8_plus?
        params[:track_total_hits] = true
      end

      @build_query_params = default_query_params.merge(params)
    end

    # Internal: The set of default query parameters that #query_params will
    # be merged into at execution time.
    #
    # Returns a Hash that will be part of the Hash passed as URL params for the query.
    def default_query_params
      defaults = {
        timeout: GitHub.es_query_timeout,
      }
      # Set shard preference if configured. See
      # http://www.elasticsearch.org/guide/en/elasticsearch/reference/current/search-request-preference.html#search-request-preference
      defaults[:preference] = preference if preference
      defaults
    end

    # Internal: Subclasses should provide any specific query paramters they
    # need via this method.
    #
    # Returns a Hash that will be passed as URL params for the query.
    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def query_params
      {}
    end

    # Internal: Construct the query document from the various parts defined in
    # the Query object. Subclasses should provide implementions for the
    # following methods:
    #
    # * build_query
    # * build_filter
    # * build_sort
    # * build_aggregations
    # * build_highlight
    #
    # Returns the query document as a Hash.
    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def query_document
      h = { query: build_query }

      filter = build_filter
      h[:post_filter] = filter unless filter.blank?

      sort = build_sort
      h[:sort] = sort unless sort.blank?

      if aggregations?
        aggregations = build_aggregations
        h[:aggregations] = aggregations unless aggregations.blank?
      end

      if highlight?
        hl = build_highlight
        unless hl.blank?
          hl = hl.merge(highlight) if highlight.is_a? Hash  # merge in default options
          h[:highlight] = hl
        end
      end

      h[:_source] = source_fields
      h[:from]    = offset
      h[:size]    = per_page

      h
    end

    # Internal: Construct the count query document from the various parts
    # defined in the Query object. Subclasses should provide implementions for
    # the following methods:
    #
    # * build_query
    # * build_filter
    #
    # Returns the count query document as a Hash.
    def count_document
      h = { query: build_query }

      filter = build_filter
      h[:filter] = filter unless filter.blank?

      h
    end

    # Internal: Construct the count query document from the various parts
    # defined in the Query object. Subclasses should provide implementions for
    # the following methods:
    #
    # * build_query
    # * build_filter
    #
    # Returns the count_with_timeout query document as a Hash.
    def count_with_timeout_document
      h = { query: build_query }

      filter = build_filter
      h[:post_filter] = filter unless filter.blank?

      h[:size] = 0

      h
    end

    # Internal: Construct the query by combining the `:query` and `:filter`
    # portions of the search into a single bool query with a filter. We include logic to
    # handle filter only queries and query only queries.
    # their own implementation.
    #
    # Returns nil.
    def build_query
      qd = query_doc
      filter = build_query_filter

      if filter && qd
        qd = {
          bool: {
            must: qd,
            filter: filter,
          },
        }
      elsif filter
        qd = { constant_score: { filter: filter } }
      elsif !qd
        qd = { match_all: {} }
      end

      qd
    end

    # Internal: Constructs the actual `:query` portion of the query
    # document. This will later be wrapped in a filtered query if search
    # qualifiers were also used.
    #
    # Returns the search query Hash.
    sig { returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
    def query_doc; end

    # Internal: Construct the query filter hash.
    #
    # Returns nil or the global filter hash.
    def build_query_filter
      filter = ::Search::Filters::BoolFilter.new(filter_hash, aggregations)
      filter.build
    end

    # Internal: Construct the global filter.
    #
    # Returns nil or the global filter hash.
    def build_filter
      return unless aggregations.present?

      hash = filter_hash.select { |name| aggregations.include? name }
      filter = Search::Filters::BoolFilter.new(hash.values)
      filter.build
    end

    # Internal: Construct the sort options. Subclasses should override and
    # provide their own implementation.
    #
    # Returns nil.
    sig do
      returns(T.nilable(T.any(
        String,
        T::Hash[T.untyped, T.untyped],
        T::Array[T.any(T::Hash[T.untyped, T.untyped], String)],
      )))
    end
    def build_sort; end

    # Internal: Construct the search aggregations. Subclasses should override and
    # provide their own implementation.
    #
    # Returns nil.
    def build_aggregations
      return unless aggregations?

      hash = {}
      aggregations.each { |aggregation| hash.update terms_aggregation(aggregation) }
      hash
    end

    # Internal: Construct the highlighting options. Subclasses should override
    # and provide their own implementation. This method will not be invoked if
    # the `highlight` attribute is false.
    #
    # Returns nil.
    def build_highlight; end

    # Internal: Accessor method for the FilterBuilder.
    #
    # Returns a FilterBuilder instance.
    def builder
      @builder ||= FilterBuilder.new qualifiers
    end

    # Internal: Construct a sort section that can be used to sort the results
    # of a search.
    #
    # fields - An Array of tuples containing the field name and the sort direction
    # args   - Optional values to add directly to the sort section,
    #          or mapping between the sort fields and the actual field that sorts.
    #          One field can map to more than one actual field,
    #          all of them will be applied in sequence with the same direction.
    #
    # Examples
    #
    #   build_sort_section( ['forks', 'asc'] )
    #   #=> [{'forks' => 'asc'}]
    #
    #   build_sort_section( ['stars', 'desc', 'forks', 'asc'] )
    #   #=> [{'stars' => 'desc'}, {'forks' => 'asc'}]
    #
    #   build_sort_section( ['stars', 'desc'], '_score' )
    #   #=> [{'stars' => 'desc'}, '_score']
    #
    #   build_sort_section( ['version', 'desc'], { 'version' => ['version_major', 'version_minor', 'version_patch'] } )
    #   #=> [{ 'version_major' => 'desc'}, { 'version_minor' => 'desc'}, { 'version_patch' => 'desc'}]
    #
    # Returns an Array of sort fields
    def build_sort_section(fields, *args)
      map = args.extract_options!

      sort = []
      Array(fields).each_slice(2) do |field, direction|
        next unless map.key? field
        Array(map[field]).each do |sort_field|
          sort << { sort_field => direction }
        end
      end
      sort.concat(args)
      sort.empty? ? nil : sort
    end

    # Internal: Construct the Search::Response object
    # that is returned when executing a query.
    # Subclasses may override this method to include different or
    # additional options.
    sig do
      overridable
      .params(
        response_class: T.class_of(Search::Results),
        elasticsearch_response: T.nilable(T::Hash[String, T.untyped]),
        options: T::Hash[Symbol, T.untyped],
      )
      .returns(Search::Results[T.untyped])
    end
    def build_response(response_class, elasticsearch_response, options)
      response_class.new(elasticsearch_response, options)
    end

    # Internal: Helper method that will construct a `terms` aggregation for the
    # given field. The field must be present in the `aggregation_fields` list and
    # it must be delcared as one of the `aggregations` for the query.
    #
    # field - The field to aggregation on as a Symbol
    #
    # Returns a terms aggregation Hash.
    def terms_aggregation(field)
      return {} unless aggregations? && aggregations.include?(field)

      aggregation = { terms: { field: field, size: aggregations_size } }

      keys = aggregation_fields - [field]
      filters = filter_hash.values_at(*keys)
      filters.compact!

      if filters.present?
        {
          field => {
            filter: Search::Filters::BoolFilter.new(filters).build,
            aggregations: { terms: aggregation },
          },
        }
      else
        {
          field => aggregation,
        }
      end
    end

    # Internal: subclass can override this to change the
    # default size value in the aggregation terms clause
    #
    # Returns a number
    def aggregations_size
      self.class.per_page_default
    end

    # Internal: Helper method that will grab the search fields from the `in`
    # field pass in as part of the query phrase. The search fields will be
    # returned as an Array of lowercased Strings. This methods supports
    # multiple `in` values; those values can be space separated or comma
    # separated.
    #
    # Returns an Array of Strings (possibly empty).
    def search_in
      return @search_in if defined?(@search_in)
      qual = qualifiers.delete :in
      @search_in = qual.nil? ? [] : Array(qual.must)
      return @search_in if @search_in.empty?

      @search_in.map! { |str| str.split(/[,\s]/) }
      @search_in.flatten!
      @search_in.map! { |str| str.downcase }
    end

    # Internal: Returns an empty filter Hash. Each subclass should build their
    # own filter list.
    def filter_hash
      {}
    end

    # Internal: Helper method that will validate a query string. An invalid
    # query is one that is too long (more than 256 characters) or has too
    # many NOT / AND / OR clauses (more than 5).
    #
    # Returns true for a valid query; false for an invalid query.
    def valid_query?

      if query.length > 256
        @invalid_reason = "The search is longer than 256 characters."
        return false
      end

      if query.scan(/(?:^|\s+)(NOT|AND|OR|&&|\|\|)(?:\s+|$)/).length > 5
        @invalid_reason = "More than five AND / OR / NOT operators were used."
        return false
      end

      ary = query.split(/\s+/)
      if !ary.empty? && ary.all? { |str| str =~ /\A\s*(?:NOT|AND|OR|&&|\|\|)\s*\z/ }
        @invalid_reason = "The search contains only logical operators (AND / OR / NOT) without any search terms."
        return false
      end

      filter_hash.each do |_name, filter|
        next if filter.valid?
        @invalid_reason = filter.invalid_reason
        return false
      end

      true
    end

    # A String describing why this query is invalid. This will only be set if
    # `valid_query?` returns `false`.
    attr_reader :invalid_reason

    REASON_EMPTY_QUERY = "None of the search qualifiers apply to this search type."

    ############################################################################
    # Instrumentation Methods
    ############################################################################

    # Instrumentation
    # Internal: Instruments a hydro event for search execution.
    # query   - a hash representing the body of the ES query
    # params  - a hash of HTTP GET query params
    # results - a Search::Results object from an executed query
    def instrument_execute(query, params, results)
      payload = instrumentation_payload(query, params, results)
      GlobalInstrumenter.instrument "search.execute", payload
    end

    # Internal: construct the payload for instrument_execute
    def instrumentation_payload(query, params, results)
      payload = {
        actor: current_user,
        escaped_query: escaped_query,
        max_score: results.max_score,
        page_number: page || 1,
        per_page: per_page,
        query: user_query,
        results: results.results_for_hydro,
        search_context: context,
        search_server_timed_out: results.timed_out?,
        search_server_took_ms: results.time,
        search_type: search_types,
        total_results: results.total,
      }
      payload[:originating_request_id] = originating_request_id if originating_request_id.present?
      payload[:es_query] = instrument_query(query, params) if query

      payload
    end

    # Internal: populate the es_query child protobuf for the search.execute event
    def instrument_query(query, params)
      # format the URL, params, query body as ES-ready GET request would
      url = Addressable::URI.parse(index.client.url)
      params[:routing] = params[:routing].join(",") if params && params[:routing].is_a?(Array)

      if params && params[:type]
        doc_types = params[:type].is_a?(Array) ? params[:type].join(",") : params[:type]
        url.path = "#{index.name}/#{doc_types}/_search"
        url.query_values = params
      else
        # fall back to not providing doc type(s) in path, or query params
        doc_types = "UNKNOWN"
        url.path = "#{index.name}/_search"
      end

      # build the payload[:es_query] child protobuf
      {
        index: index.name,
        doc_type: doc_types,
        es_version: index.client.version,
        target_headers: {},
        url: url.to_s,
        body: query.to_json,
        submitted_at: Time.now.utc,
      }
    end

    # Internal: returns an array of search types for the current query,
    # used for instrumentation
    def search_types
      # T.must ensures that the class name will not be nil (as it would be with an anonymous class)
      search_type = T.must(self.class.name).demodulize.underscore.gsub("_query", "")

      # TODO (@Mattamorphic) (Epic - https://github.com/github/issues/issues/15080) Remove this when we reconcile pagnation and conditional issue classes (pagination is a subclass)
      search_type = "conditional_issue" if search_type == "cursor_paginated_conditional_issue"

      search_type = search_type_from_index if search_type == "issue"
      search_type = [search_type] unless search_type.is_a?(Array)

      search_type
    end

    # Internal: Subclasses should override this with their own implementation.
    # Used to override the search type for a query based on the index.
    def search_type_from_index
      nil
    end

    # Internal: logs query metadata associated with the given `at` value
    def log_query(at:, data_hash: {}, error: nil)
      index_name = index&.name.to_s

      log_payload = {
        "code.namespace" => self.class.name,
        "code.function" => at,
        "db.elasticsearch.path_parts.index" => index_name,
        "gh.elasticsearch.query" => user_query,
        "gh.elasticsearch.escaped_query" => escaped_query,
        "gh.search.server.timed_out" => Elastomer::QueryStats.timed_out?,
        "gh.actor.id" => current_user&.id,
        "gh.actor.spammy" => current_user&.spammy?,
        "gh.search.context" => context,
        "gh.catalog_service" => catalog_service.present? ? catalog_service : GitHub.context[:catalog_service],
        "http.client_ip" => GitHub.context[:actor_ip],
        "gh.request_id" => GitHub.context[:request_id],
        "http.request.header.x_original_user_agent" => GitHub.context[:user_agent],
        "gh.context.from" => GitHub.context[:from],
        "gh.originating_request_id" => originating_request_id,
        # these fields are only set for web requests
        "gh.context.url" => GitHub.context[:url],
        # these fields are only set for api requests
        "http.route" => GitHub.context[:api_route],
        "gh.api.query" => GitHub.context[:query_string],
      }

      log_payload.merge!(data_hash)

      if error.present?
        log_payload.merge!(error_to_hash(error))
        GitHub.logger.error("Query metadata error", log_payload)
      else
        GitHub.logger.info("Query metadata", log_payload)
      end
    end

    # Internal: Search cache keys have very high cardinality. Log data
    # associated with query keys so we can generate reports on how effective
    # our cache strategy is.
    def log_cache_key(cache_key_name)
      log_payload = {
        "code.namespace" => self.class.name,
        "code.function" => cache_key_name.to_s,
        "gh.search.cache_key.value" => send(cache_key_name),
      }
      GitHub.logger.info("Search cache keys", log_payload)
    end

    # Internal: returns the unparsed phrase provided to the query
    def user_query
      phrase || @raw_phrase
    end

    # Internal: converts an error to a hash of error attributes, used for logging
    #
    # Returns a hash of error attributes
    def error_to_hash(error)
      error_hash = {}

      return error_hash if error.blank?

      error_hash[:exception] = error

      error_hash["gh.search.error.name"] = stats_name(error)

      case error
      when ElastomerClient::Client::Error
        if error.error
          data = error.error["root_cause"]
          data = data.first if data.is_a?(Array)

          return error_hash if data.blank?

          data.each do |key, value|
            error_hash["gh.search.error.#{key}"] = value&.inspect
          end
        end
      end

      error_hash
    end

    # Internal: Given an exception, return a suitable name to use for reporting
    # error counts to the GitHub stats endpoint.
    #
    # exception - an elastomer client exception class
    #
    # Returns a suitable stats string name
    def stats_name(exception)
      if exception.message =~ %r/parse_exception/i
        "parse-failure"
      else
        exception.class.name.split("::").last.underscore.tr("_", "-")
      end
    end

    # Internal: Given an exception, return a boolean indicating if the exception should be tracked.
    # Untracked exceptions are recorded as metrics instead.
    def tracked_exception?(exception)
      return false if exception.is_a?(ElastomerClient::Client::TimeoutError)
      return false if exception.is_a?(ElastomerClient::Client::RequestError) && exception.message =~ %r/parse_exception/i

      true
    end

    def datadog_search_cluster
      if GitHub.multi_tenant_enterprise?
        stamp = Elastomer::Router.stamp
        es_major_version = index.client.version.split(".").first
        return "proxima-search-es#{es_major_version}-#{stamp}"  # e.g., proxima-search-es8-prod-ae-01
      end
      index.cluster_name
    end

    # Internal: Return an Array of DataDog tags.
    #
    # exception - optional exception instance.
    def datadog_tags(exception = nil)
      logged_in = current_user.present? ? "true" : "false"
      spammy_actor = current_user&.spammy? ? "true" : "false"
      classname = T.must(self.class.name).demodulize.underscore
      complex = complex? ? "true" : "false"


      tags = [
        "context:#{context}",
        "search_cluster:#{datadog_search_cluster}",
        "index:#{index.name}",
        "logged_in:#{logged_in}",
        "spammy_actor:#{spammy_actor}",
        "classname:#{classname}",
        "complex:#{complex}",
      ]
      unless legacy_es_cluster_metric_disabled?
        tags << "es_cluster:#{index.cluster_name}"
      end

      tags << "error:#{stats_name(exception)}" if exception.present?

      tags
    end

    # Internal: Returns a Boolean.
    #
    # A complex query is one with one or more non-AND Boolean operators. Override this method in your subclass with a
    # proper implementation if it supports complex queries.
    sig { overridable.returns(T.nilable(T::Boolean)) }
    private def complex?
      false
    end

    def execute_results_log_metadata(results)
      {
        "gh.search.server.timed_out" => results.timed_out,
      }
    end

    # List of ElasticSearch supported operators
    OPERATORS = %w(AND OR NOT || &&).freeze

    # Wrap every word on quotes except it's already quoted or it's part of a quoted substring
    sig { params(value: T.nilable(String)).returns(T.nilable(String)) }
    def quote_words(value)
      return nil if value.nil?

      words = value.split(" ")
      return value unless words.size > 1
      return value if (OPERATORS & words).any?

      total_quotes = 0
      words.map do |word|
        word_quotes = word.count('"')
        total_quotes += word_quotes

        # Do not quote a word that has already a quote
        next word if word_quotes > 0

        # Do not quote numbers
        next word if word =~ /\A\d+\Z/

        # If we saw an odd number of quotes, we're inside a quoted text
        next word if total_quotes.odd?

        "\"#{word}\""
      end.join(" ")
    end

    def legacy_es_cluster_metric_disabled?
      GitHub.flipper.enabled?(:disable_legacy_es_cluster_metric)
    end
  end  # Query

end  # Search
