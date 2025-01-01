require "graphql_timer"

module API
  class Schema < GraphQL::Schema
    use GraphQL::Dataloader

    query API::Types::Root
    mutation API::Types::Mutation
    max_depth 13

    instrument :query, GraphQLTimer

    TYPES = {
      "Package" => Package,
      "API::Types::Package" => Package,
    }

    def self.id_from_object(object, type_definition, query_ctx)
      if TYPES.key?(type_definition.name)
        GraphQL::Schema::UniqueWithinType.encode(TYPES[type_definition.name].name, object.id)
      else
        object.id
      end
    end

    def self.object_from_id(id, query_ctx)
      type_name, item_id = GraphQL::Schema::UniqueWithinType.decode(id)

      type = TYPES[type_name]
      if type
        type.find(item_id)
      else
        raise GraphQL::ExecutionError.new("Invalid object id: #{type_name}:#{item_id}")
      end
    end

    def self.resolve_type(abstract_type, object, context)
      if object.is_a?(Package) || object.is_a?(API::Types::Package)
        API::Types::Package
      end
    end
  end

  GraphQL::Relay::BaseConnection.register_connection_implementation(
    Queries::VersionRangeDependentsQuery,
    API::ConnectionWrappers::VersionRangeDependentsWrapper)

  GraphQL::Relay::BaseConnection.register_connection_implementation(
    Queries::AbstractRepositoryDependentsQuery,
    API::ConnectionWrappers::Delegator)

  GraphQL::Relay::BaseConnection.register_connection_implementation(
    Queries::AbstractPackageDependentsQuery,
    API::ConnectionWrappers::Delegator)

  GraphQL::Relay::BaseConnection.register_connection_implementation(
    Queries::RepositoryPackageReleasesQuery,
    API::ConnectionWrappers::RepositoryPackageReleasesWrapper)

  GraphQL::Relay::BaseConnection.register_connection_implementation(
    Queries::RepositoryDependentsQuery,
    API::ConnectionWrappers::Delegator)
end
