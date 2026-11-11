# typed: true
# frozen_string_literal: true

module Search
  module Queries

    # The fuzzy finder is used to search for users via logins and emails.
    # Instead of requiring an exact match, however, some small variations are
    # allowed between the query and the results.
    #
    # So a search for `tim.peas@github.com` would match
    # `tim.pease@github.com` (notice the trailing `e` on `pease`).
    #
    # This class should **never** be exposed to the general public. It
    # searches over all the emails associated with a user's account; this
    # includes the private emails and billing emails. It is intended for staff
    # use only.
    class UserFuzzyFinder < UserQuery

      # Default to returning 20 search results
      def self.per_page_default
        20
      end

      # Create a fuzzy user query to execute against the `users` search index.
      def initialize(opts = {})
        super(opts)
        self.source_fields = opts.fetch(:source_fields, false)
      end

      # Set the query to the given value. The value will be converted to a
      # String and then downcased.
      def query=(value)
        super(value.to_s.downcase)
      end

      # Internal: Helper method that will validate a query string.
      #
      # Returns true for a valid query; false for an invalid query.
      def valid_query?
        return false unless super

        if query.empty?
          @invalid_reason = "The search query is empty."
          return false
        end

        true
      end

      def normalize(results)
        super results

        results.each do |hit|
          highlights = hit["highlight"]

          exact = false
          exact |= (query == highlights["all_emails"].first.downcase) if highlights["all_emails"]
          exact |= (query == highlights["login"].first.downcase) if highlights["login"]

          hit["_exact"] = exact
        end

        results
      end

      # Internal: Constructs the search query based on the `query` attribute.
      #
      # Returns the search query Hash.
      def query_doc
        { bool: {
          should: [
            { multi_match: {
              query: query,
              fields: %w[login all_emails],
              operator: "AND",
            } },
            fuzzy(:login),
            fuzzy(:all_emails),
          ],
          minimum_should_match: 1,
        } }
      end

      # Internal: Construct a fuzzy query for the given document field name.
      #
      # field - the document field name to query
      #
      # Returns a fuzzy query Hash
      def fuzzy(field)
        { fuzzy: { field => {
          value: query,
          max_expansions: 10,
          prefix_length: 0,
        } } }
      end

      def build_highlight
        { encoder: :default,
          require_field_match: true,
          pre_tags: [""],
          post_tags: [""],
          type: "plain",
          fields: {
            login: { number_of_fragments: 0 },
            all_emails: { number_of_fragments: 0 },
        } }
      end

      def build_sort
        nil
      end

      def build_filter
        nil
      end

      def build_aggregations
        nil
      end

    end  # UserFuzzyFinder
  end  # Queries
end  # Search
