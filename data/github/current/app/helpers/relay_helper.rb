# typed: true
# frozen_string_literal: true

module RelayHelper
  extend T::Helpers

  requires_ancestor { ApplicationController::AuthenticatedSystem }
  requires_ancestor { ApplicationController }

  def early_hints?
    GitHub.early_hints? && FeatureFlag.vexi.enabled_or_raise?(:early_hints, current_user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
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
    # query: string
    # variables: Hash
    sig { params(name: String, variables: T.nilable(T::Hash[String, T.untyped])).void }
    def initialize(name:, variables:)
      @name = name
      @variables = variables
    end
    attr_reader :query, :variables, :name

    def for_link_header
      "<#{API_PATH}?#{query_string}>; rel=preload; as=fetch; crossorigin=use-credentials"
    end

    def graphql_query_id
      queries = GitHubUI::Manifest.new.relay_manifest[:queries]
      query_id = queries.find { |_, query| query[:name] == name }&.first

      raise "unable to find query id for #{name}" if query_id.nil?
      query_id
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

    API_PATH = "/_graphql"
  end


end
