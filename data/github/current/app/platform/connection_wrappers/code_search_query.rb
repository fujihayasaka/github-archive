# typed: true
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    # Knows how to call the Blackbird client proxy class and returns the data as a GraphQL connection object.
    class CodeSearchQuery < ConnectionWrappers::Base
      include GitHub::Memoizer

      # Intermediate and internal data-only result classes
      Response = Struct.new(:errors, :facets, :results, :total_count, :error_count, :facet_count)
      CodeSearchQueryEdge     = Struct.new(:node, :cursor)

      # Identifier passed to Blackbird to identify the Blackbird API consumer.
      BLACKBIRD_GRAPHQL_CONTEXT = "graphql"

      # Artifically cap the maximum number of errors and facets we want to return to the user. Technically speaking,
      # Blackbird _could_ return 1 error per query character (which is limited to 1000 characters currently)
      # but paging might be overkill here and instead we can just show the first N errors returned.
      #
      # Blackbird will also return a max of five facets per type (four types) so lets hard-cap this at 20
      # in case we ever add more facet types and this array becomes too large.
      #
      # Keeping these public so the CodeSearch connection can use it for its description building.
      ERRORS_LIMIT = 50
      FACETS_LIMIT = 20

      # Don't expose these to the outside world, we are using them internally in this class only.
      private_constant :BLACKBIRD_GRAPHQL_CONTEXT, :CodeSearchQueryEdge, :Response

      attr_reader :limit, :offset, :query, :page

      def initialize(
        items,
        context:,
        arguments: nil,
        max_page_size: 100,
        field: nil,
        first: nil,
        last: nil,
        after: nil,
        before: nil,
        **kwargs
      )
        @query   = arguments[:query]
        @limit   = determine_limit(max_page_size, first, last)
        @offset  = determine_offset(last, before, after, field)
        @page    = determine_page(limit, @offset)
        super(
          items,
          arguments: arguments,
          first: first,
          last: last,
          after: after,
          before: before,
          field: field,
          max_page_size: max_page_size,
          context: context,
          **kwargs
        )
      end

      def approximate_count
        # short-circuit if we received a failed count response
        return nil if internal_count_response[:failed]

        internal_count_response[:count]
      end

      def errors
        response.then { |res| res.errors }
      end

      def facets
        response.then { |res| res.facets }
      end

      def results
        response.then { |res| res.results }
      end

      def total_count
        response.then { |res| res.total_count }
      end

      def error_count
        response.then { |res| res.error_count }
      end

      def facet_count
        response.then { |res| res.facet_count }
      end

      memoize def edges
        response.then do |res|
          res.results.each_with_index.map do |result, index|
            cursor = CursorGenerator.generate_cursor(offset + index)

            CodeSearchQueryEdge.new(result, cursor)
          end
        end
      end

      memoize def edge_nodes
        edges.then { |edges| edges.map(&:node) }
      end

      memoize def page_info
        edges.then do |edges|
          PageInfo.new(
            has_next_page:,
            has_previous_page:,
            start_cursor: edges.first&.cursor,
            end_cursor: edges.last&.cursor,
          )
        end
      end

      # This will return the result from a call to ::BlackbirdSearch::Client#count which
      # will be in the shape of a hash: { failed: false, count: 9988, mode: 1 }
      memoize def internal_count_response
        ::BlackbirdSearch::Client.count(
          current_user,
          actor: blackbird_actor,
          tenant: blackbird_tenant,
          query:,
          request_timeout: blackbird_request_timeout,
          context: BLACKBIRD_GRAPHQL_CONTEXT,
        )
      end

      # This makes the actual call to the Blackbird client proxy class.
      # We are exposing this method as part of the public API for bubbling up the raw data for debugging.
      memoize def internal_response
        # The underlying Blackbird class will load some data via the User#user_metadata association so we
        # have to make sure it is loaded asynchronously.
        current_user.async_user_metadata.then do
          ::BlackbirdSearch::Client.query(
            current_user,
            cap_filter,
            actor: blackbird_actor,
            tenant: blackbird_tenant,
            query:,
            results_per_page: limit,
            page_number: page - 1, # Blackbird paging is 0-based
            document_location_limit: 5,
            request_timeout: blackbird_request_timeout,
            snippet_options: {
              desired_width: 120,
              high_density_snippet_max_lines: 20,
            },
            context: BLACKBIRD_GRAPHQL_CONTEXT,
          ).tap do |blackbird_response|
            if blackbird_response[:failed]
              twirp_error = blackbird_response[:error_message]

              # handle the specific twirp error for `resource_exhausted` type and raise a `Platform::Errors::RateLimited` error instead
              if twirp_error.code == :resource_exhausted
                raise Platform::Errors::RateLimited, "Internal API rate-limited with code #{twirp_error.code}: #{twirp_error.msg}"
              end

              raise Platform::Errors::Internal, "Internal API failed with code #{twirp_error.code}: #{twirp_error.msg}"
            end
          end
        end
      end

      memoize def incomplete?
        internal_response.then do |internal_response|
          internal_response[:incomplete_results] || false
        end
      end

      private

      def has_next_page
        total_count.then do |total_count|
          offset + limit < total_count
        end
      end

      def has_previous_page
        offset > 0
      end

      def determine_offset(last, before, after, field)
        if last
          raise Errors::MissingBackwardsPaginationArgument.new(field) unless before

          offset = CursorGenerator.resolve_cursor(before).to_i
          offset -= last
        elsif after
          offset = CursorGenerator.resolve_cursor(after).to_i
          # We want to see _after_ the cursor, so increment the skip to bypass that commit
          offset += 1
        else
          offset = 0
        end

        offset
      end

      # Taken from app/platform/connection_wrappers/commit_history.rb
      # Get the smallest, non-nil number
      def determine_limit(max_page_size, first, last)
        limit = max_page_size
        if first && first < limit
          limit = first
        end
        if last && last < limit
          limit = last
        end
        limit
      end

      def determine_page(limit, offset)
        return 1 if limit.zero? # don't divide by zero

        # We want the 1-based page number, so we need to add 1 to the offset
        # The max will ensure we don't go below 1.
        # The Blackbird API is 0-based but we will let that be a very specific Blackbird implementation detail
        # and take care of that right before we make the call to Blackbird.
        [(offset / limit).floor + 1, 1].max
      end

      memoize def response
        internal_response.then do |internal_response|
          make_response(query, internal_response)
        end
      end

      # Top-level conversion from the Blackbird result to GraphQL model instances.
      def make_response(query, raw_response)
        async_repositories(raw_response).then do |repos|
          repos_by_id = repos.compact.index_by(&:id)

          # make_facets will return an array of facets, so we need to flatten it.
          facets      = raw_response[:facets].flat_map { |raw_facet_hash| make_facets(raw_facet_hash) }.take(FACETS_LIMIT)
          results     = raw_response[:results].map { |raw_result_hash| make_result(raw_result_hash, repos_by_id) }
          errors      = raw_response[:errors].map { |raw_error_hash| make_error(raw_error_hash) }.take(ERRORS_LIMIT)
          total       = raw_response[:result_count]
          error_count = raw_response[:errors].length
          facet_count = raw_response[:facets].length

          Response.new(errors, facets, results, total, error_count, facet_count)
        end
      end

      # Returns a Promise[[Repository]] for all the repository IDs in the raw_response results.
      # We know that the current user has access to them since Blackbird processed its own authz and
      # returned these repository IDs.
      def async_repositories(raw_response)
        repo_ids = raw_response[:results].map { |raw_result_hash| raw_result_hash[:repo_id] }.compact

        Loaders::ActiveRecord.load_all(::Repository, repo_ids)
      end

      # Convert raw Blackbird result to GraphQL model instance.
      def make_result(raw_result_hash, repos_by_id)
        snippets = raw_result_hash[:snippets].map { |snippet| make_snippet(snippet) }
        repo_id = raw_result_hash[:repo_id]
        repository = repo_id ? repos_by_id[repo_id.to_i] : nil

        Models::CodeSearchResult.new(
          path: raw_result_hash[:path],
          commit_sha: raw_result_hash[:commit_sha],
          ref_name: raw_result_hash[:ref_name],
          blob_sha: raw_result_hash[:blob_sha],
          match_count: raw_result_hash[:match_count],
          language: Models::CodeSearchLanguage.new(
            name: raw_result_hash[:language_name],
            id: raw_result_hash[:language_id],
            color: raw_result_hash[:language_color]
          ),
          repo_owner_id: raw_result_hash[:owner_id],
          repo_id:,
          repo_nwo: raw_result_hash[:repo_nwo],
          snippets: snippets,
          repository:
        )
      end

      # Convert raw Blackbird snippet to GraphQL model instance.
      def make_snippet(raw_snippet_hash)
        snippet_format = raw_snippet_hash[:format].to_s

        # Exchange the name for the value (i.e. "SNIPPET_FORMAT_HTML" => 2)
        # Note: This will raise an error if the constant doesn't exist.
        format_value = Blackbird::Query::V1::SnippetFormat.const_get(snippet_format)

        Models::CodeSearchSnippet.new(
          end_position: raw_snippet_hash[:end],
          ending_line_number: raw_snippet_hash[:ending_line_number],
          jump_to_line_number: raw_snippet_hash[:jump_to_line_number],
          lines: raw_snippet_hash[:lines],
          match_count: raw_snippet_hash[:match_count],
          score: raw_snippet_hash[:score],
          start_position: raw_snippet_hash[:start],
          starting_line_number: raw_snippet_hash[:starting_line_number],
          type: format_value,
        )
      end

      # Convert raw Blackbird error to GraphQL model instance.
      def make_error(raw_error_hash)
        # NOTE: This will be a symbol defined in Blackbird::Query::V1::ErrorType, or an integer if there is a new
        # value in the Protocol Buffer response that is not reflected in the installed version of blackbird-client.
        # This is important to allow because it allows adding error types the backend without breaking the frontend.
        type    = raw_error_hash[:type]
        message = raw_error_hash[:message]
        ranges  = (raw_error_hash[:ranges] || []).map { |raw_range| make_range(raw_range) }

        case type
        when :ERROR_TYPE_UNSPECIFIED
          # NOTE: This is the default protocol buffer value for the enum. It should not be used by the server.
          Models::CodeSearchUnspecifiedError.new(message:)
        when :ERROR_TYPE_QUERY_PARSING_FATAL
          Models::CodeSearchQueryParsingFatalError.new(message:, ranges:)
        when :ERROR_TYPE_QUERY_PARSING_WARNING
          suggestion = raw_error_hash[:suggestion]
          Models::CodeSearchQueryParsingWarningError.new(message:, ranges:, suggestion:)
        when :ERROR_TYPE_TIMEOUT
          Models::CodeSearchTimeoutError.new(message:)
        when :ERROR_TYPE_SEARCH_RESULTS_INCONSISTENT_WARNING
          Models::CodeSearchInconsistentResultsError.new(message:)
        when :ERROR_TYPE_ACTOR_NOT_AUTHORIZED
          Models::CodeSearchActorNotAuthorizedError.new(message:)
        when :ERROR_TYPE_SCOPE_UNSATISFIABLE
          Models::CodeSearchScopeUnsatisfiableError.new(message:)
        when :ERROR_TYPE_RESULTS_INCOMPLETE
          Models::CodeSearchIncompleteResultsError.new(message:)
        when :ERROR_TYPE_MISSING_INACCESSIBLE_REPO_ORG
          # TODO: We need a different error for missing owner.
          # This may be an NWO _or_ an owner name.
          name_with_owner = raw_error_hash[:missing_or_inaccessible_repo_org_nwo]
          Models::CodeSearchInaccessibleRepoError.new(message:, name_with_owner:, ranges:)
        else
          # NOTE: There is a new error type in the enum that has not been added to the client.
          # Return CodeSearchUnspecifiedError as a default.
          Models::CodeSearchUnspecifiedError.new(message:)
        end
      end

      def make_range(raw_range_hash)
        Models::CodeSearchErrorRange.new(
          start_position: raw_range_hash[:start],
          end_position: raw_range_hash[:end]
        )
      end

      # Note that this is just a recommendation for Blackbird to finish its response by this threshold.
      # If it reaches the threshold then it will return whatever processed results it has at that point.
      # https://github.com/github/github/blob/cd00e62e26c5373d606ca0a0d4a8a3d52e631c53/lib/platform/schema.rb#L25
      def blackbird_request_timeout
        seconds = GitHub.request_timeout({}) - 1

        Google::Protobuf::Duration.new(seconds:)
      end

      def blackbird_actor
        ip_address = @context[:ip]
        token      = @context[:request_token]

        ::BlackbirdSearch::Client.api_actor(current_user, ip_address, token)
      end

      def blackbird_tenant
        ::BlackbirdSearch::Client.tenant(GitHub::CurrentTenant.get)
      end

      def current_user
        @context[:viewer]
      end

      def cap_filter
        @context[:cap_filter]
      end

      # Convert raw Blackbird facets to GraphQL model instance.
      # In this case facet_hash is a hash of the form: { type: "", entries: [] }
      def make_facets(raw_facet_hash)
        type = raw_facet_hash[:kind].to_s

        # Exchange the name for the value (i.e. "FACET_KIND_PATH" => 3)
        # Note: This will raise an error if the constant doesn't exist.
        # Reference the FacetKind constant for enum values/mappings.
        type_value = ::Blackbird::Query::V1::FacetKind.const_get(type)

        raw_facet_hash[:entries].map do |entry|
          name  = entry[:name]
          query = entry[:query]

          case type_value
          when 0
            Models::CodeSearchInvalidFacet.new(query:)
          when 1
            name_with_owner = entry[:name]

            Models::CodeSearchRepoFacet.new(query:, name_with_owner:)
          when 2
            color = entry[:language_color]

            Models::CodeSearchLanguageFacet.new(name:, query:, color:)
          when 3
            Models::CodeSearchPathFacet.new(path: name, query:)
          else
            raise Errors::Internal, "Unknown facet kind: #{type}"
          end
        end
      end
    end
  end
end
