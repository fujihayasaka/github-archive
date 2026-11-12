module GraphQLHelpers
  def sort_by(field)
    ->(hash) { hash[:node][field] }.curry
  end

  def query(query, variables = {})
    post "/query", params: { query: query, variables: variables.to_json }
  end

  def graphql_id(type, object)
    GraphQL::Schema::UniqueWithinType.encode(type, object.id)
  end
  alias global_object_id graphql_id

  def graphql_errors
    Array(JSON.parse(response.body)["errors"]).map { |error| error["message"] }
  end

  def results
    body = JSON.parse(response.body)
    if body["errors"].present?
      raise "Error: #{body["errors"]}"
    else
      Hash(body["data"]).deep_symbolize_keys
    end
  end
end
