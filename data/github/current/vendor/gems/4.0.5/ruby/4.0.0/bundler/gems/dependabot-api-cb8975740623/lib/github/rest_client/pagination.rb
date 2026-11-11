# frozen_string_literal: true

module GitHub
  class RESTClient < ::Octokit::Client
    module Pagination
      # Pager provides an enumerable interface for Octokit's REST API, as well as some
      # helper methods for paging behavior and metadata.
      class Pager
        include Enumerable

        def initialize(options = {}, &block)
          @fetch = block
          @page_num = 1
          @max_page = options[:max_pages]
        end

        # Each implements the enumerable interface around paginated API calls
        def each(&)
          # @data is set in fetch_next_page.  If @data is not set yet,
          # we haven't yet fetched any pages.  Fetch the first page to start
          # enumerating data.
          fetch_next_page unless defined?(@data)

          while @data
            yield(@data)

            @page_num += 1
            return if @max_page.present? && @page_num > @max_page

            fetch_next_page
          end
        end

        def total_pages
          # @total_pages is calculated during fetch_next_page.  If @total_pages
          # is not set yet, we haven't yet fetched any pages.  Fetch the first page
          # to calculate the value.
          fetch_next_page unless defined?(@total_pages)

          @total_pages
        end

        private

        def fetch_next_page
          response = @fetch.call
          @data = response&.data
          @total_pages = total_pages_for_response(response) unless defined?(@total_pages)
        end

        def total_pages_for_response(response)
          return 0 unless response && response.rels[:last]

          last_page_url = URI.parse(response.rels[:last].href)
          CGI.parse(last_page_url.query).fetch("page", [1]).first.to_i
        end
      end

      def paginate(url, options = {}, &)
        options = options.dup
        enumerator_options = options.delete(:enumerator)

        return super if enumerator_options.nil? || enumerator_options == false

        opts = send(:parse_query_and_convenience_headers, options)
        opts[:query][:per_page] ||= @per_page || 100

        current_response = nil
        Pager.new(parse_enumerator_options(enumerator_options)) do
          if current_response.nil?
            request(:get, url, opts.dup)
            current_response = @last_response
            next current_response
          end

          # if there is no next page or if the client is rate limited, return nil
          next unless current_response.rels[:next] && rate_limit.remaining.positive?

          # set the current response to the response for the next page
          @last_response = current_response = current_response.rels[:next].get(headers: opts[:headers])
          current_response
        end
      end

      private

      def parse_enumerator_options(enumerator_options)
        return enumerator_options if enumerator_options.is_a?(Hash)
        return enumerator_options.to_h if enumerator_options.is_a?(Array)

        {}
      end
    end
  end
end
