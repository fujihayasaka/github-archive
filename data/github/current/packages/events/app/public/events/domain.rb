# typed: strict
# frozen_string_literal: true

module Events
  class Domain < GH::Domain::Base
    extend T::Sig

    include Repositories::Domain::Provider

    # Public: returns whether or not a provided repository is locked for
    # migrations or importing
    #
    # Returns Boolean.
    sig { params(repository: T.nilable(Repositories::IRepository)).returns(T::Boolean) }
    def model_importing?(repository)
      return true if GitHub.importing?

      return false if repository.nil?
      ActiveRecord::Base.connected_to(role: :reading) do
        repository.locked_on_migration? || repository.is_importing?
      end
    rescue ArgumentError, NoMethodError, ActiveRecord::RecordNotFound
      # this means we were unable to retrieve a target repository causing exception.
      # ignore and return false.
      false
    end

    # Represents the GraphQL IDs for a model.
    class GraphQLIDs < T::Struct
      const :global_relay_id, T.nilable(String)
      const :next_global_id, T.nilable(String)
    end

    # Public: Retrieves the graphql ID's for a model in a defensive manner. Calling `global_relay_id` and
    # `next_global_id` on some models can return an ArgumentError if the model happens not to be available in GraphQL.
    # We cannot simply swallow the ArgumentError, because it is reported to Sentry within Platform::Helpers::NodeIdentification.async_to_next_global_id.
    sig { params(model: T.anything).returns(Events::Domain::GraphQLIDs) }
    def graphql_ids(model)
      ids = {
        global_relay_id: nil,
        next_global_id: nil
      }

      # Check and see if the model has a GraphQL type.
      # This logic is pulled from Platform::Helpers::NodeIdentification.async_to_next_global_id: https://github.com/github/github/blob/master/lib/platform/helpers/node_identification.rb#L53
      has_type = T.unsafe(model).respond_to?(:platform_type_name) && Platform::Helpers::NodeIdentification.type_from_object(model) != nil
      return GraphQLIDs.new unless has_type

      # Unfortunately we have to do this using unsafe since there is no Sorbet compatible generic type
      # that includes these methods. These are part of GitHub::Relay::GlobalIdentification which is not typed.
      begin
        ids[:global_relay_id] = T.unsafe(model).global_relay_id if T.unsafe(model).respond_to?(:global_relay_id)
      rescue ArgumentError
        # We should ideally not get these unless the above check is missing something.
        GitHub.dogstats.increment("hooks.domain.graphql_ids.error", tags: ["call:global_relay_id", "error:argument_error"])
      end

      begin
        ids[:next_global_id] = T.unsafe(model).next_global_id if T.unsafe(model).respond_to?(:next_global_id)
      rescue ArgumentError
        # We should ideally not get these unless the above check is missing something.
        GitHub.dogstats.increment("hooks.domain.graphql_ids.error", tags: ["call:next_global_id", "error:argument_error"])
      end

      GraphQLIDs.new(ids)
    rescue Exception # rubocop:todo Lint/GenericRescue
      # We should ideally not get these unless the above check is missing something.
      # Because the GraphQL ID logic is very confusing and behaves differently in Enterprise mode, we want to be very safe with this method so that
      # we don't inadvertantly raise an error when publishing events.
      GitHub.dogstats.increment("hooks.domain.graphql_ids.error", tags: ["call:graphql_ids", "error:unknown"])
      GraphQLIDs.new
    end

    # Public: returns whether or not a provided repository is disabled or
    # is an advisory workspace.
    sig { params(repository: T.nilable(Repositories::IRepository)).returns(T.nilable(T::Boolean)) }
    def has_target_repository_disabled_webhooks(repository)
      repository&.disabled? || advisory_workspace?(repository)
    end

    # Public: returns whether or not a provided repository is an advisory workspace.
    # Returns Boolean.
    sig { params(repository: T.nilable(Repositories::IRepository)).returns(T.nilable(T::Boolean)) }
    def advisory_workspace?(repository)
      T.cast(repository, T.nilable(Repository))&.advisory_workspace? && !T.cast(repository, Repository).parent_advisory&.repository&.feature_enabled?(:maintainer_love_advisory_workspaces_can_use_actions) # rubocop:todo GitHub/AvoidCast
    end

    # Public: instantiates and returns the correct event action string for a given event action enum
    sig { params(event_action_enum: Symbol).returns(String) }
    def action_for_event_action_enum(event_action_enum)
      event_action_enum.inspect.delete_prefix(":EVENT_ACTION_").downcase
    end


    # Public: This call-through serves as a single point of entry to `Api::Serializer`
    # using a common set of options for all events.
    sig { params(serialize_method: Symbol, object: T.anything, options: T::Hash[Symbol, T.anything]).returns(T.untyped) }
    def api_serialize(serialize_method, object, options = {})
      Api::Serializer.serialize(serialize_method, object, { serialize_login: :display }.merge(options)) # rubocop:disable GitHub/ApiSerializeInHookPayloads
    end
  end
end
