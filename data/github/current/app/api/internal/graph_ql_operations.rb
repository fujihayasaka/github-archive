# typed: true
# frozen_string_literal: true

class Api::Internal::GraphQlOperations < Api::Internal

  # sync endpoint for GraphQL::Pro::OperationStore to register operations
  # required HMAC authentication to extract client information for the operation store
  post "/internal/graphql/operations", operation_id: :internal do
    # rewrite path_info because GraphQL::Pro::OperationStore::Endpoint expects to be mounted to a path
    request.path_info = "/"

    # build out the 'Authorization' header that GraphQL::Pro::OperationStore::Endpoint expects
    request.env["HTTP_AUTHORIZATION"] = "GraphQL::Pro #{env[:internal_client_id]} hmac_redacted"

    GraphQL::Pro::OperationStore::Endpoint.new(schema_class_name: "Platform::Schema").call(env)
  end

  def require_request_hmac?
    true
  end

end
