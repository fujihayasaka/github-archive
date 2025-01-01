# typed: true
# frozen_string_literal: true

module Search
  # Normalizes search results from ElasticSearch. Instances of this class are
  # returned from the Query class' execute method.
  #
  class Results
    extend T::Generic

    include Enumerable

    # `Elem` is required by Enumerable.
    # It is the type of each member contained in the
    # collection returned by Search::Results#each.
    Elem = type_member { { fixed: T.untyped } }

    # `Model` is the type of each member contained in the
    # collection returned by Search::Results#models.
    Model = type_member

    # Creates a new, empty search results. This is handy to use after an error
    # has occurred but you still want a results object.
    def self.empty(total: 0, error_message: nil, error_details: nil)
      new({ "hits" => { "hits" => [], "total" => total } }, page: 1, error_message:, error_details:)
    end

    attr_reader :total, :total_relation, :time, :page, :per_page, :max_offset, :max_offset_window, :timed_out, :max_score

    sig { returns(T.nilable(String)) }
    attr_reader :error_message

    sig { returns(T.nilable(T::Hash[T.any(String, Symbol), T.untyped])) }
    attr_reader :error_details

    attr_accessor :results, :aggregations

    # Create a new Results collection from the ElasticSearch response Hash.
    # The response should be the raw JSON document converted to a Ruby Hash;
    # no other processing needs to be performed.
    #
    # response - The response Hash returned from ElasticSearch.
    # opts     - Optional arguments Hash for pagination.
    #   :page     - The current page number.
    #   :per_page - The number of results per page.
    #
    def initialize(response, opts = {})
      @aggregations = {}
      @time = response["took"].to_i
      #using this variable as we don't have current_user context here to check FF
      @search_action_packages_enabled = false

      has_results = response["hits"].present?

      # ES8-COMPATIBILITY: ES 8 returns an object for total hits rather than a plain integer.
      # Use that to determine how to unpack the response.
      was_es_8_response = has_results && response.dig("hits", "total").is_a?(Hash)

      if has_results && was_es_8_response
        @total = response.dig("hits", "total", "value")
        @total_relation = response.dig("hits", "total", "relation").to_sym
        @results = response.dig("hits", "hits")
        @max_score = (response.dig("hits", "max_score") || 0).to_f
      elsif has_results
        @total = response.dig("hits", "total").to_i
        @total_relation = :eq
        @results = response.dig("hits", "hits")
        @max_score = (response.dig("hits", "max_score") || 0).to_f
      else
        @total = 0
        @total_relation = :eq
        @results = []
        @max_score = 0
      end

      @aggregations = response["aggregations"] if response.key? "aggregations"

      @timed_out = response["timed_out"] || false
      @more_results = @timed_out || response["more_results"] || false

      @page          = opts.fetch(:page, nil)
      @per_page      = opts.fetch(:per_page, ::Search::Query::per_page_default)
      @max_offset    = opts.fetch(:max_offset, ::Search::Query::max_offset_default)
      @max_offset_window = opts.fetch(:max_offset_window, ::Search::Query::max_offset_window_default)
      @error_message = opts.fetch(:error_message, nil)
      @error_details = opts.fetch(:error_details, nil)
    end

    sig do
      override
      .params(block: T.proc.params(arg: Elem).returns(BasicObject))
      .returns(T::Array[Elem])
    end
    def each(&block)
      results.each(&block)
    end

    def empty?
      results.empty?
    end

    def timed_out?
      @timed_out
    end

    def more_results?
      @more_results
    end

    def search_action_packages_enabled!
      @search_action_packages_enabled = true
    end

    def search_action_packages_enabled?
      @search_action_packages_enabled
    end

    # Returns whether or not the result was truncated
    #
    # In recent versions of Elasticsearch, there is performance optimization with a side effect that we can't count
    # all the results. Instead we can count up to some number. If the count has been truncated then this will return
    # true. However, we haven't implemented this in the base class yet because most elastomer clients are using an
    # older version of ES.
    #
    # Read more at https://www.elastic.co/guide/en/elasticsearch/reference/7.8/search-your-data.html#track-total-hits
    def count_truncated?
      false
    end

    # Public: Returns whether or not the search encountered an error.
    # An error may not always indicate a problem with the search library or server, but
    # could be the result of user input. In cases where user inputs could be the cause of
    # parse exceptions, callers can also use #parse_error? to differentiate between
    # errors that are probably user-caused vs. backend errors.
    sig { returns(T::Boolean) }
    def error?
      error_message.present?
    end

    # Public: A convenience method to check if the error is a parse failure.
    # Parse failures do not always indicate a programming error, or a server error, but
    # contextually can sometimes be caused by user inputs. While ideally Query#valid_query? should
    # reject invalid queries, it is imperfect, and sometimes bad inputs leak through.
    # In those cases, dependents of these search results may wish to differentiate between
    # errors they believe are user-caused vs. developer-caused.
    #
    sig { returns(T::Boolean) }
    def parse_error?
      return false unless error_details.present?
      error_details&.fetch("gh.search.error.name", nil) == "parse-failure"
    end

    # Public: can be overridden by child classes, indicates whether the result was rate limited
    def rate_limited?
      false
    end

    def size
      results.size
    end
    alias :length :size

    def [](index)
      results[index]
    end

    sig { returns(T::Array[Model]) }
    def models
      results.map { |result| result["_model"] }.compact
    end

    def paginated_models
      pagination_enabled!

      WillPaginate::Collection.create(
        current_page,
        per_page,
        total_entries,
      ) do |pager|
        pager.replace(models)
      end
    end

    # Here be will_paginate compatibility
    def total_entries
      pagination_enabled!

      total < max_offset ? total : max_offset
    end

    def current_page
      pagination_enabled!
      page
    end

    # Assert that we have a page number
    def pagination_enabled!
      return unless page.nil?
      raise ArgumentError,
        "Pagination is not available when `page` is not passed to #{self.class.name}.new."
    end

    # Returns the total number of pages available for these search results.
    #
    # The total number of search results that will ever be returned is
    # capped. The farther you offset into a set of search results, the more
    # work the search index has to do. This adversely affects performance;
    # hence it is capped.
    def total_pages
      pagination_enabled!

      # max_offset checks the beginning of the range (ceil),
      # while max_result_window limits any row in the range (floor)
      max_pages_offset = (max_offset / per_page.to_f).ceil
      max_pages_window = (max_offset_window / per_page.to_f).floor
      max_pages = [max_pages_offset, max_pages_window].min

      total_pages = (total / per_page.to_f).ceil
      (total_pages < max_pages) ? total_pages : max_pages
    end

    # Returns the previous page number of nil if there is no previous page.
    def previous_page
      pagination_enabled!
      current_page > 1 ? (current_page - 1) : nil
    end

    # Returns the next page number of nil if there is no next page.
    def next_page
      pagination_enabled!
      current_page < total_pages ? (current_page + 1) : nil
    end

    # The current offset into the actual search results.
    def offset
      pagination_enabled!
      per_page * (current_page - 1)
    end

    # Returns true if the current page is greater than the total number of pages.
    def out_of_bounds?
      pagination_enabled!
      current_page > total_pages
    end

    # Remove entries in the results array for which the block returns true. This
    # means the search index is out of sync with the database so report it to
    # Failbot.
    #
    # block - A block that must accept a single Hit object and return true if
    #         it should be removed from the results array.
    #
    # Returns the Array of missing entries.
    #
    def reject!(&block)
      missing = results.select(&block)
      @results = results - missing
      missing
    end

    # Return the list of language aggregations for which we have a
    # Linguist::Language object.
    def languages
      aggregation = @aggregations["language_id"] || @aggregations["code.language_id"]
      aggregation = aggregation["terms"] if aggregation && aggregation["terms"]

      if aggregation
        aggregation["buckets"].each do |bucket|
          bucket["key"] = Search.language_name_from_id(bucket["key"])
        end
      end

      @languages ||= if languages = aggregation && Search::Aggregations::Terms.new(aggregation)
        Search::Aggregations::Percentages.build(languages).select { |t| t.language.present? }
      else
        []
      end
    end

    # Return the list of state aggregations.
    def states
      @states ||= if state_terms
        Search::Aggregations::Percentages.build(state_terms)
      else
        []
      end
    end

    # Return a hash of counts for any aggregated states that match the query.
    def state_counts
      counts = {}
      if state_terms.present? && state_terms.items.present?
        state_terms.items.each do |state_aggregation|
          counts[state_aggregation["key"]] = state_aggregation["doc_count"]
        end
      end
      counts
    end

    # Return the list of package_type and package_subtype aggregations.
    def package_types
      @package_types ||= if package_type_terms || package_subtype_terms
        aggregation_package_type = Search::Aggregations::Percentages.build(package_type_terms) if package_type_terms
        if search_action_packages_enabled?
          aggregation_package_subtype = Search::Aggregations::Percentages.build(package_subtype_terms) if package_subtype_terms
          # Only accept package_subtype actions as a package_type to be searchable
          aggregation_package_subtype = aggregation_package_subtype.select { |t| t.term == "actions" }
          return Array(aggregation_package_type) | Array(aggregation_package_subtype)
        end
        return aggregation_package_type
      else
        []
      end
    end

    # Return a hash of counts for any aggregated package types that match the query.
    def package_type_counts
      counts = {}
      if package_type_terms.present? && package_type_terms.items.present?
        package_type_terms.items.each do |package_type_aggregation|
          counts[package_type_aggregation["key"]] = package_type_aggregation["doc_count"]
        end
      end
      if package_subtype_terms.present? && package_subtype_terms.items.present?
        package_subtype_terms.items.each do |package_subtype_aggregation|
          counts[package_subtype_aggregation["key"]] = package_subtype_aggregation["doc_count"]
        end
      end
      counts
    end

    # Internal: Grabs information from the results for the hydro instrumention.
    # Currently, pretty straight mapping but will eventually be grabbing
    # information about the models in the results.
    #
    # Returns an array of result information for hydro instrumentation.
    def results_for_hydro
      return unless @results.is_a?(Array)

      @results.map do |result|
        next unless result.is_a?(Hash)
        hydro_payload = {
          search_id: result["_id"],
          index: result["_index"],
          score: result["_score"],
        }
        if result_object = result["_model"]
          hydro_payload.merge!({
            id: result_object.id,
            model_name: result_object.class.name.demodulize,
            global_relay_id: result_object.try(:global_relay_id),
            url: build_url(result),
          })
        end
        hydro_payload
      end.compact
    end

    def includes_public_repositories?
      lazy.any? { |result| result.repository_count.positive? }
    end

    private

    def build_url(result)
      source = result["_source"]
      url = result["_model"].try(:permalink)
      index_name = Elastomer.get_index_name_from_result(result)

      case index_name
      when "commits"
        unless source.blank? || url.blank?
          "#{url}/commit/#{source["hash"]}"
        end

      when "code-search"
        unless source.blank? || url.blank?
          path = source.values_at("commit_sha", "path", "filename").compact.join("/")
          "#{url}/blob/#{path}"
        end

      else
        url
      end
    end

    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def state_terms
      @state_terms ||= begin
        aggregation = @aggregations.dig("state", "terms") || @aggregations["state"]
        Search::Aggregations::Terms.new(aggregation) if aggregation
      end
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def package_type_terms
      @package_type_terms ||= begin
        aggregation = @aggregations.dig("package_type", "terms") || @aggregations["package_type"]
        if search_action_packages_enabled?
          sub_type_aggregation = @aggregations.dig("package_subtype", "terms") || @aggregations["package_subtype"]
          if sub_type_aggregation.present?
            container_bucket = aggregation["buckets"].find { |bucket| bucket["key"] == "container" }
            actions_bucket = sub_type_aggregation["buckets"].find { |bucket| bucket["key"] == "actions" }
            # container doc_count should be the difference of the two
            container_bucket["doc_count"] -= actions_bucket["doc_count"] if container_bucket.present? && actions_bucket.present?
            # replace aggregation["buckets"] with new container bucket minus the sub_type doc_count
            aggregation["buckets"].delete_if { |bucket| bucket["key"] == "container" }
            aggregation["buckets"].push(container_bucket) if container_bucket.present? && container_bucket["doc_count"] > 0
          end
        end
        Search::Aggregations::Terms.new(aggregation) if aggregation
      end
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def package_subtype_terms
      @package_subtype_terms ||= begin
        aggregation = @aggregations.dig("package_subtype", "terms") || @aggregations["package_subtype"]
        Search::Aggregations::Terms.new(aggregation) if aggregation
      end
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator
  end
end
