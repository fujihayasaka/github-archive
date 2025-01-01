# typed: true
# frozen_string_literal: true

module Api::Limiters::GraphqlHelper

  # Public: Determine if the incoming request is for a GraphQL endpoint. Our
  # specific GraphQL implementation has a preference for POST requests for
  # query execution.
  #
  # request - Rack::Request instance.
  #
  # Returns true if GraphQL request, false otherwise.
  def graphql_request?(request)
    return false if request.request_method != "POST"
    !graphql_path(request).nil?
  end

  # Public: Extract the GraphQL path from the incoming request.
  #
  # request - Rack::Request instance.
  #
  # Returns String if GraphQL path is present, false otherwise.
  def graphql_path(request)
    if match = ::Api::GraphQL::PATH_REGEX.match(request.path_info)
      match[0].downcase
    end
  end
end
