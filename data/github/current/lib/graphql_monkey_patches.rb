# typed: true
# frozen_string_literal: true

require "graphql_extensions/max_query_depth"
require "graphql_extensions/int_cast"

require "graphql_extensions/visibility_for_builtins"
require "graphql_extensions/map_to_service_for_builtins"
require "graphql_extensions/scopes_for_builtins"
require "graphql_extensions/upcoming_change_for_builtins"

# GraphQL monkey-patches
module GraphQL

  # because of the way we have ActiveSupport::Deprecation configured in tests,
  # any deprecation warnings are interpreted as failures. This eats some of the
  # Graphql-Ruby deprecation warnings since we aren't moving to GraphQL-Ruby 2 yet.
  # it also prevents them from spamming prod logs. So define a base module as a pattern
  # that we can use to suppress deprecation warnings.
  module Deprecation
    def self.warn(message)
      if defined?(ActiveSupport)
        ActiveSupport.deprecator.warn(message)
      else
        Kernel.warn(message)
      end
    end
  end

  # Make the built-ins (scalars, introspection) respond to our customizations
  EXTENSIONS_FOR_BUILTINS = [
    GraphQLExtensions::VisibilityForBuiltIns,
    GraphQLExtensions::ScopesForBuiltIns,
    GraphQLExtensions::UpcomingChangeForBuiltIns,
    GraphQLExtensions::MapToServiceForBuiltIns,
  ]

  EXTENSIONS_FOR_BUILTINS.each do |extension|
    Schema::Object.extend(extension)
    GraphQL::Types::Relay::Node.extend(extension)
    Schema::Scalar.extend(extension)
    Schema::Union.extend(extension)
    Schema::Interface::DefinitionMethods.include(extension)
    Schema::Enum.extend(extension)
    Schema::EnumValue.include(extension)
    Schema::Field.include(extension)
    Schema::Argument.include(extension)
  end

  # Lawd fahgive me.
  # So many things depend on a previous graphql-batch setup where
  # the executor was always present.
  module Batch
    class Executor
      def self.current
        if existing = Thread.current[THREAD_KEY]
          existing
        else
          start_batch(Platform::Batch::RequestExecutor)
          Thread.current[THREAD_KEY]
        end
      end
    end
  end

  # We want to change the database connection only for the actual `resolve` calls in mutations
  # so we run less queries on the primary DB.
  class Schema
    class Mutation
      # The only differences in this call are:
      # - enforcing the `writing` connection when calling `resolve`
      #   and syncing the `resolve` result in case it returns a promise. This change will only run if the
      #  `read_arguments_from_replicas` flag in context is enabled.
      # - reporting how many reads happen in arguments and auth stages.
      # - this calls a `before_resolve` method if it exists, allowing mutations to split up some
      #   logic to run ahead of time, e.g. to load/modify arguments using a DB replica, and then
      #   calls the `resolve` method using those modified args returned from `before_resolve`
      def resolve_with_support(**args)
        ready_val = if args.any?
          ready?(**args)
        else
          ready?
        end
        context.schema.after_lazy(ready_val) do |is_ready, ready_early_return|
          if ready_early_return
            if is_ready != false
              raise "Unexpected result from #ready? (expected `true`, `false` or `[false, {...}]`): [#{is_ready.inspect}, #{ready_early_return.inspect}]"
            else
              ready_early_return
            end
          elsif is_ready
            query_tracker = context[:query_tracker]
            if query_tracker
              context[:mutation_name] = self.class.graphql_name.underscore
              mysql_counts_before_args = query_tracker.mysql_counts.deep_dup
              mysql_dog_tags = query_tracker.dog_tags + ["mutations_on_read:#{context[:read_arguments_from_replicas].present?}", "mutation_name:#{context[:mutation_name]}"]
            end
            # Then call each prepare hook, which may return a different value
            # for that argument, or may return a lazy object
            load_arguments_val = load_arguments(args)
            context.schema.after_lazy(load_arguments_val) do |loaded_args|
              if query_tracker
                mysql_counts_after_args = query_tracker.mysql_counts.deep_dup
                GitHub.dogstats.distribution("platform.query.sql_count.arguments.reads.total", mysql_counts_after_args[:read][:total] - mysql_counts_before_args[:read][:total], tags: mysql_dog_tags)
                GitHub.dogstats.distribution("platform.query.sql_count.arguments.reads.on_primary", mysql_counts_after_args[:read][:on_primary] - mysql_counts_before_args[:read][:on_primary], tags: mysql_dog_tags)
              end

              @prepared_arguments = loaded_args
              Schema::Validator.validate!(self.class.validators, object, context, loaded_args, as: @field)
              # Then call `authorized?`, which may raise or may return a lazy object
              authorized_val = if loaded_args.any?
                authorized?(**loaded_args)
              else
                authorized?
              end
              context.schema.after_lazy(authorized_val) do |(authorized_result, early_return)|
                if query_tracker
                  mysql_counts_after_auth = query_tracker.mysql_counts.deep_dup
                  GitHub.dogstats.distribution("platform.query.sql_count.auth.reads.total", mysql_counts_after_auth[:read][:total] - mysql_counts_after_args[:read][:total], tags: mysql_dog_tags)
                  GitHub.dogstats.distribution("platform.query.sql_count.auth.reads.on_primary", mysql_counts_after_auth[:read][:on_primary] - mysql_counts_after_args[:read][:on_primary], tags: mysql_dog_tags)
                end

                # If the `authorized?` returned two values, `false, early_return`,
                # then use the early return value instead of continuing
                if early_return
                  if authorized_result == false
                    early_return
                  else
                    raise "Unexpected result from #authorized? (expected `true`, `false` or `[false, {...}]`): [#{authorized_result.inspect}, #{early_return.inspect}]"
                  end
                elsif authorized_result
                  if loaded_args.any?
                    # in case the `before_resolve` method returns a promise, ensure that it's resolved here
                    modified_args = self.respond_to?(:before_resolve) ? Promise.resolve(self.before_resolve(**loaded_args)).sync : loaded_args
                    if query_tracker
                      mysql_counts_after_before_resolve = query_tracker.mysql_counts.deep_dup
                      GitHub.dogstats.distribution("platform.query.sql_count.before_resolve.reads.total", mysql_counts_after_before_resolve[:read][:total] - mysql_counts_after_auth[:read][:total], tags: mysql_dog_tags)
                      GitHub.dogstats.distribution("platform.query.sql_count.before_resolve.reads.on_primary", mysql_counts_after_before_resolve[:read][:on_primary] - mysql_counts_after_auth[:read][:on_primary], tags: mysql_dog_tags)
                    end
                  else
                    modified_args = []
                  end
                  # Finally, all the hooks have passed, so resolve it
                  if context[:read_arguments_from_replicas]
                    ActiveRecord::Base.connected_to(role: :writing) do
                      result = if modified_args.any?
                        public_send(self.class.resolve_method, **modified_args)
                      else
                        public_send(self.class.resolve_method)
                      end

                      # In case the `resolve` method returns a promise, ensure that it's resolved here
                      # so the writing role is not overriden.
                      Promise.resolve(result).sync
                    end
                  else
                    if modified_args.any?
                      public_send(self.class.resolve_method, **modified_args)
                    else
                      public_send(self.class.resolve_method)
                    end
                  end
                else
                  raise GraphQL::UnauthorizedFieldError.new(context: context, object: object, type: field.owner, field: field)
                end
              end
            end
          end
        end
      end
    end
  end

  # Skip authorize calls for __typename
  # https://github.com/rmosolgo/graphql-ruby/pull/3446
  module Introspection
    class DynamicFields
      def self.authorized_new(object, context)
        new(object, context)
      end
    end
  end

  Analysis::AST::MaxQueryDepth.prepend(GraphQLExtensions::MaxQueryDepth)
  Client::Schema::ScalarType.prepend(GraphQLExtensions::IntCast)
end
