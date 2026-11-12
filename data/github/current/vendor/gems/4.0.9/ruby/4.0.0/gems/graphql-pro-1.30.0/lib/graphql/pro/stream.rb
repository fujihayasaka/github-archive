# frozen_string_literal: true
require "forwardable"

module GraphQL
  module Pro
    class Stream < Schema::Directive
      description "Directs the executor to deliver this list item-by-item, after the requested `initialCount`."

      locations(GraphQL::Schema::Directive::FIELD)

      argument :if, Boolean, required: false,
        default_value: true,
        description: "If false, this field _won't_ be streamed."

      argument :label, String, required: false,
        description: "A unique label to identify the stream payload."

      argument :initial_count, Integer, required: false, default_value: 0,
        description: "The number of items to return in the initial response."

      def self.resolve_each(object, arguments, context, &block)
        if arguments[:if]
          initial_count = arguments[:initial_count]
          path = context[:current_path]
          if path.last < initial_count
            yield
          else
            defer = context[:defer] ||= Pro::Defer::Deferred.new(context)
            defer.deferrals << Pro::Defer::Deferral.new(
              block: block,
              path: path,
              context: context,
              label: arguments[:label],
            )
          end
        else
          yield
        end
      end

      class StreamNext
        if defined?(GraphQL::Execution::Finalizer)
          include GraphQL::Execution::PostProcessor
          include GraphQL::Execution::Finalizer
        end

        def initialize(ast_nodes:, field_definition:, parent_type:, context:, label:, initial_count:)
          @ast_nodes = ast_nodes
          @field_definition = field_definition
          @parent_type = parent_type
          @context = context
          @label = label
          @initial_count = initial_count
          @streamables = nil
          @next_streamable_idx = 0
        end

        def path=(new_path)
          if @streamables
            @streamables[@next_streamable_idx].path = new_path
            @next_streamable_idx += 1
          end
          super
        end

        def finalize_graphql_result(query, result_data, result_key)
          # pass
        end

        def inspect
          "#<#{self.class}##{object_id} field=#{@field_definition.path} type=#{@parent_type.to_type_signature} ...>"
        end

        def after_resolve(field_results)
          @streamables = []
          field_results.map { |fr|
            enumerator = fr.is_a?(Enumerator) ? fr : fr.to_enum
            streamable = Streamable.new(ast_nodes: @ast_nodes, parent_type: @field_definition.type, context: @context, label: @label, initial_count: @initial_count, enumerator: enumerator)
            @context[:defer].deferrals << streamable
            @streamables << streamable
            streamable.get_initial_items
          }
        end


        class Streamed
          include Defer::Serializable

          def initialize(result:, query:, path:, label:, has_next:)
            @execution_result = result
            @query = query
            @path = path
            @label = label
            @has_next = has_next
          end

          attr_reader :path, :label, :execution_result

          def data
            @data ||= @execution_result["data"]
          end

          def errors
            @errors ||= @execution_result["errors"]
          end

          def has_next?
            @has_next
          end
        end

        class Streamable
          def initialize(ast_nodes:, parent_type:, context:, label:, initial_count:, enumerator:)
            @ast_nodes = ast_nodes
            @parent_type = parent_type
            @context = context
            @label = label
            @terminated = false
            @i = 0
            @enumerator = enumerator
            @size = enumerator.size
            @path = nil
            @initial_count = initial_count
          end

          attr_writer :path


          def terminated?
            @terminated
          end

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
              query = @context.query
              exec_result = query.run_partials([{ object: obj, path: obj_path }]).first
              streamed_result = Streamed.new(
                result: exec_result,
                has_next: has_next,
                query: query,
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


          NO_ITEMS = [].freeze
          private_constant :NO_ITEMS

          def finalize_graphql_result(query, result_data, key)
            # TODO this is not right: it should keep executing here,
            # not shove unresolved objects directly into the response
            result_data[key] = get_initial_items
          end

          def get_initial_items
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
                has_next = @context[:defer].deferrals.any? { |s| s.is_a?(Streamable) && !s.terminated? }
                [ has_next, nil ]
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
                @context.query.handle_or_reraise(error)
              rescue GraphQL::ExecutionError => exec_err
                error = exec_err
              end
            end

            Streamed.new(
              result: { "errors" => [error.to_h] },
              has_next: false,
              query: @query,
              path: path,
              label: @label
            )
          end
        end
      end

      class << self
        def resolve_field(ast_nodes, parent_type, field_definition, objects, arguments, context)
          if field_definition.type.list? && arguments[:if]
            context[:defer] ||= GraphQL::Pro::Defer::Deferred.new(context)
            StreamNext.new(ast_nodes: ast_nodes, field_definition: field_definition, parent_type: parent_type, initial_count: arguments[:initial_count], context: context, label: arguments[:label])
          else
            nil
          end
        end
      end

      def self.use(schema)
        schema.directive(self)
      end
    end
  end
end
