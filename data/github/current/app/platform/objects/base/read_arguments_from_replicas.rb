# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Base < GraphQL::Schema::Object
      # This adds an API to enable reading mutation arguments from replicas.
      module ReadArgumentsFromReplicas
        def read_arguments_from_replicas!(require_client_permission: false, enable_selective_writes: false)
          @read_arguments_from_replicas = true
          @read_arguments_from_replicas_require_client_permission = require_client_permission
          @read_arguments_from_replicas_enable_selective_writes = enable_selective_writes
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

        def selective_write_enabled_for_mutation?
          selective_writes_enabled = defined?(@read_arguments_from_replicas_enable_selective_writes) && @read_arguments_from_replicas_enable_selective_writes

          return false unless selective_writes_enabled

          # Only enable selective writes if the feature is enabled
          GitHub.flipper[:gql_read_from_replicas_selective_write].enabled?(Platform::MutationActor.new(self))
        end
      end
    end
  end
end
