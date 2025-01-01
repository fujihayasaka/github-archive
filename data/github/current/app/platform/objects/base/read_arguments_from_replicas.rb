# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Base < GraphQL::Schema::Object
      # This adds an API to enable reading mutation arguments from replicas.
      module ReadArgumentsFromReplicas
        def read_arguments_from_replicas!(require_client_permission: false)
          @read_arguments_from_replicas = true
          @read_arguments_from_replicas_require_client_permission = require_client_permission
        end

        def read_arguments_from_replicas?(client_permits_replicas: false)
          enabled = defined?(@read_arguments_from_replicas) && @read_arguments_from_replicas
          require_client_permission = defined?(@read_arguments_from_replicas_require_client_permission) && @read_arguments_from_replicas_require_client_permission

          return false unless enabled

          # Some mutations only read from replicas if the client has given permission to do so
          return false if require_client_permission && !client_permits_replicas

          # Only read from replicas if the feature is enabled
          GitHub.flipper[:gql_read_arguments_from_replicas].enabled?(Platform::MutationActor.new(self))
        end
      end
    end
  end
end
