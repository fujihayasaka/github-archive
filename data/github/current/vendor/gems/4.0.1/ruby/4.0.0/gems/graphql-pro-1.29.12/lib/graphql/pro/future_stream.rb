# frozen_string_literal: true
require "forwardable"

module GraphQL
  module Pro
    # This is a future implementation of the `@stream` directive.
    # It's better than the current `GraphQL::Pro::Stream` because
    # it supports lazily streaming list items (via Ruby's `Enumerator`).
    # Also, under the hood, it uses a new first-class execution primitive, `GraphQL::Query::Partial`,
    # so it will be easier to support (ie, less hacky...).
    #
    # It's compatible with the previous `@stream` directive **EXCEPT** for one big thing:
    # it requires list fields to opt into streaming with `context.streamable(...)`.
    #
    # `context.streamable(...)` should wrap the field's return value, for example:
    #
    # ```ruby
    # def items
    #  # Somehow produce a Ruby Enumerator:
    #  streaming_database_items = MyDatabase.fetch(:items)
    #  context.streamable(streaming_database_items)
    # end
    # ```
    #
    # If the value passed to `context.streamable` isn't an `Enumerator`, then `.to_enum`
    # is called on it. (This supports `Array`s, `ActiveRecord::Relation`s, etc, out of the box.)
    class FutureStream < Schema::Directive
      def self.use(schema)
        schema.directive(self)
      end

      module ContextExtension
        def streamable(enumerable)
          FutureStream.streamable(self, enumerable)
        end
      end

      class StreamableExtension < GraphQL::Schema::FieldExtension
        def after_resolve(object:, arguments:, context:, value:, memo:)
          FutureStream.streamable(context, value)
        end
      end

      module FieldExtension
        def initialize(*args, streamable: false, **kwargs, &block)
          super(*args, **kwargs, &block)
          if streamable
            extension(StreamableExtension)
          end
        end
      end

      ::GraphQL::Schema::Field.prepend(FieldExtension)
      ::GraphQL::Query::Context.include(ContextExtension)

      graphql_name "stream"
      description "Directs the executor to deliver this list item-by-item, after the requested `initialCount`."

      locations(GraphQL::Schema::Directive::FIELD)

      argument :if, Boolean, required: false,
        default_value: true,
        description: "If false, this field _won't_ be streamed."

      argument :label, String, required: false,
        description: "A unique label to identify the stream payload."

      argument :initial_count, Integer, required: false, default_value: 0,
        description: "The number of items to return in the initial response."

      def self.streamable(context, enumerable)
        if context.schema.directives["stream"] != GraphQL::Pro::FutureStream
          return enumerable
        end

        ast_selection = Fiber[:__graphql_runtime_info][context.query].current_result.ast_node
        current_result_name = context.current_path.last
        ast_node = ast_selection.selections.find { |s| s.alias == current_result_name || s.name == current_result_name }

        if (dir_node = ast_node.directives.find { |d| d.name == "stream" }) &&
          (arguments = context.query.arguments_for(dir_node, self)) &&
          arguments[:if]
          enumerator = case enumerable
          when Enumerator
            enumerable
          else
            enumerable.to_enum
          end

          deferred = context[:defer] ||= Pro::Defer::Deferred.new(context)

          initial_count = arguments[:initial_count]

          streamable = Streamable.new(enumerator, context.query, context.current_path, arguments[:label], initial_count)
          deferred.deferrals << streamable
          streamable.get_initial_items
        else
          enumerable
        end
      end

      class Streamed
        include GraphQL::Pro::Defer::Serializable
        def initialize(execution_result, query:, path:, label:, has_next:)
          @execution_result = execution_result
          @query = query
          @path = path
          @label = label
          @has_next = has_next
        end

        attr_reader :path, :label, :execution_result

        def to_h
          h = super
          if data
            target = @query.result["data"]
            last_idx = @path.size - 1
            @path.each_with_index do |path_segment, idx|
              if idx == last_idx
                target[path_segment] = @execution_result["data"] # not isolated -- will be modified
              else
                target = target[path_segment] ||= {}
              end
            end
          end
          h
        end

        def data
          @data ||= isolate_copy(@execution_result["data"])
        end

        def errors
          @errors ||= isolate_copy(@execution_result["errors"])
        end

        def has_next?
          @has_next
        end
      end

      class Streamable
        def initialize(enumerator, query, path, label, initial_count)
          @enumerator = enumerator
          @query = case query
          when GraphQL::Query
            query
          when GraphQL::Query::Partial
            query.query
          else
            raise ArgumentError, "Expected Runnable, got: #{query.inspect}"
          end
          @path = path
          @i = 0
          @size = enumerator.size
          @initial_count = initial_count
          @label = label
          @terminated = false
        end

        def terminated?
          @terminated
        end

        NO_ITEMS = [].freeze
        private_constant :NO_ITEMS

        def get_initial_items
          return NO_ITEMS if @initial_count == 0
          items = []
          while @i < @initial_count
            @i += 1
            items << @enumerator.next
          end
          items
        rescue StopIteration
          @terminated = true
          items
        end

        # Resolve each patch and yield it.
        # Yields nothing if already terminated.
        # @yieldparam [Streamed] The result from an item of a streamed list
        def resolve_each
          while !@terminated
            obj_path = @path + [@i]
            @i += 1
            begin
              obj = @enumerator.next
            rescue StandardError => err
              @terminated = true
              # May keep raising through
              yield(build_error_response(err, obj_path))
              return nil
            end

            has_next, has_next_error_result = has_next_with_error

            exec_result = @query.run_partials([{ object: obj, path: obj_path }]).first
            streamed_result = Streamed.new(
              exec_result,
              has_next: has_next,
              query: @query,
              path: obj_path,
              label: @label
            )
            yield(streamed_result)
            if has_next_error_result
              yield(has_next_error_result)
            end
          end
        rescue StopIteration
          @terminated = true
          nil
        end

        private

        def has_next_with_error
          if @size && @i < @size
            # If we have a known size, use that
            [true, nil]
          else
            begin
              @enumerator.peek
              # if it didn't raise, there's something there (might be `false`)
              [true, nil]
            rescue StopIteration
              @terminated = true
              [
                @query.context[:defer].deferrals.any? { |s| s.is_a?(Streamable) && !s.terminated? },
                nil
              ]
            rescue StandardError => err
              @terminated = true
              [true, build_error_response(err, @path + [@i])]
            end
          end
        end

        def build_error_response(error, path)
          if error.is_a?(GraphQL::ExecutionError)
            # ok
          else
            begin
              @query.handle_or_reraise(error)
            rescue GraphQL::ExecutionError => exec_err
              error = exec_err
            end
          end

          Streamed.new(
            { "errors" => [error.to_h] },
            has_next: false,
            query: @query,
            path: path,
            label: @label
          )
        end
      end
    end
  end
end
