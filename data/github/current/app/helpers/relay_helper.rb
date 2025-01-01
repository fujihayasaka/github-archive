# typed: true
# frozen_string_literal: true

module RelayHelper
  extend T::Helpers

  requires_ancestor { ApplicationController::AuthenticatedSystem }
  requires_ancestor { ApplicationController }

  def early_hints?
    GitHub.early_hints? && GitHub.flipper[:early_hints].enabled?(current_user)
  end

  # Set a link header instructing the browser to start downloading the initial
  # GraphQL API request so that with any luck by the time relay issues the
  # actual fetch() for it the response will be available or nearly so.
  # If the :early_hints flag is set this will attempt to transmit the preload
  # header early in the request.
  def set_preload_header(graphql_requests)
    preload_directive = Array.wrap(graphql_requests).map(&:for_link_header).join(",")

    if early_hints?
      request.send_early_hints("Link" => preload_directive)
      response.headers["X-Accel-Buffering"] = "no"
    end
    # Fallback for clients that don't understand early hints
    response.headers["Link"] = preload_directive
  end

  class GraphQLRequest
    # query: Pathname (quacks with #each_line)
    # variables: Hash
    def initialize(query:,  variables:)
      @query = query
      @variables = variables
    end
    attr_reader :query, :variables

    def for_link_header
      "<#{API_PATH}?#{query_string}>; rel=preload; as=fetch; crossorigin=use-credentials"
    end

    def graphql_query_id
      # only memoize in production because there the query does not change during the server's lifetime
      return @graphql_query_id if defined?(@graphql_query_id) && Rails.env.production? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
      query.each_line.find { |line| line.match(QUERY_PATTERN) } or raise "unable to find query id for #{query}"
      @graphql_query_id = T.must(Regexp.last_match)[1]
    end

    def variables_key
      GitHub::JSON.encode(variables)
    end

    private

    def query_string
      URI.encode_www_form(body: encoded_payload).gsub(/\+/, "%20")
    end

    def encoded_payload
      GitHub::JSON.canonical_encode(
        query: graphql_query_id,
        variables: variables
      )
    end

    # Magic comment inside a relay-compiled graphql query which contains its identifier.
    QUERY_PATTERN = %r[// @relayRequestID ([0-9a-f]{32,40})]
    API_PATH = "/_graphql"
  end


end
