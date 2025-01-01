# typed: true
# frozen_string_literal: true

module Search
  # Responsible for rendering and caching the query result count from elastic
  # search. The count partial is only cached a short time to give the appearance
  # of instantaneous results as the user clicks through the Repositories, Users,
  # and Code menu items.
  #
  # The Search::ResultsView and CodesearchController both use this class to
  # render the count partial so they can easily share the cache key.
  #
  #   query = Search::Queries::CodeQuery.new
  #   view  = Search::CountView.new(query: query)
  #   view.render # => '<span class="Counter">42</span>'
  class CountView
    # Create a view around this query's count.
    #
    # query - The Search::Query object whose count we need to cache.
    # count - The Integer count value
    # type - The type of query, issues, code, wiki, etc.
    # timed_out - True if the count query timed out and returned a subset
    def initialize(query:, count: nil, type: nil, timed_out: false)
      @query = query
      @count = Search::Results.empty(total: count) if count
      @type = type
      @more_results = timed_out
    end

    # Caches and returns the rendered count span partial. This method executes
    # a count query against elastic search only if the count is not already
    # cached.
    #
    #   <span class="Counter Counter--primary">42</span>
    #
    # Returns the HTML String for the count. <span class="Counter">0</span> is rendered for empty
    # results to make search results clear for the user when switching between tabs.
    def render
      GitHub.cache.fetch(cache_key, ttl: 3.minutes) do
        if count
          num = social_count
          view.content_tag(:span, num, class: "ml-1 js-codesearch-count Counter#{' Counter--primary' unless count.total <= 0}", "data-search-type": @type)
        end
      end
    end

    def social_count
      n = count.total
      return "0" if n == 0

      power = 3 * (Math.log10(n.abs) / 3).floor

      prefixes = {
        3 => "K",
        6 => "M",
        9 => "B",
        12 => "T",
      }

      plus = @more_results || count.more_results? ? "+" : ""

      return "#{n}#{plus}" unless prefixes.keys.include?(power)

      "#{n / 10**power}#{prefixes[power]}#{plus}"
    end

    # Returns true if the count for this query is already in memcache. This can
    # be called before `render` to prevent an actual count query from running
    # against elastic search.
    #
    # Returns a boolean indicating whether this count is cached.
    def cached?
      GitHub.cache.exist?(cache_key)
    end

    private

    def cache_key
      @query.count_with_timeout_cache_key
    end

    def count
      @count ||= @query.count_with_timeout
    end

    # Returns a 'view' object with ActionView helper methods included. This
    # avoids polluting CountView's interface with dozens of helper methods.
    def view
      @view ||= begin
        view = Object.new
        view.extend(ActionView::Helpers::NumberHelper)
        view.extend(ActionView::Helpers::TagHelper)
      end
    end
  end
end
