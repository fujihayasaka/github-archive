# frozen_string_literal: true
require "forwardable"

module GraphQL
  module Pro
    class Defer < Schema::Directive
      description "Directs the executor to deliver this part of the result after the initial result."

      locations(
        GraphQL::Schema::Directive::FIELD,
        GraphQL::Schema::Directive::FRAGMENT_SPREAD,
        GraphQL::Schema::Directive::INLINE_FRAGMENT
      )

      argument :if, Boolean, required: false,
        default_value: true,
        description: "If false, this field _won't_ be deferred."

      argument :label, String, required: false,
        description: "A unique label to identify the deferred payload."

      def self.resolve(object, arguments, context, &block)
        # if this directive was duplicated, `path` will be nil inside later resolve calls
        if arguments[:if] && (path = context[:current_path])
          defer = context[:defer] ||= self::Deferred.new(context)
          defer.deferrals << self::Deferral.new(block: block, path: path, context: context, label: arguments[:label])
        else
          yield
        end
      end

      class << self
        def resolve_inline_fragment(ast_node, parent_type, objects, arguments, context)
          handle_deferral(ast_node, parent_type, objects, arguments, context)
        end

        def resolve_fragment_spread(ast_node, parent_type, objects, arguments, context)
          handle_deferral(ast_node, parent_type, objects, arguments, context)
        end

        def resolve_field(ast_nodes, parent_type, _field_definition, objects, arguments, context)
          handle_deferral(ast_nodes.first, parent_type, objects, arguments, context)
        end

        private

        def handle_deferral(ast_node, parent_type, objects, arguments, context)
          if arguments[:if]
            defer = context[:defer] ||= self::Deferred.new(context)
            deferral = self::DeferralNext.new(ast_node: ast_node, parent_type: parent_type, objects: objects, context: context, label: arguments[:label])
            defer.deferrals << deferral
            deferral
          else
            nil
          end
        end
      end

      def self.use(schema)
        if schema.is_a?(Class)
          schema.directive(self)
        else
          [schema, schema.target].each do |schema_defn|
            schema_defn.directive(self.graphql_definition)
          end
        end
      end

      module Serializable
        # @return [Hash] with `path:`, either `errors:` or `data:`, and `label:`, if given.
        def to_h
          h = {
            path: path,
            hasNext: has_next?
          }

          if label
            h[:label] = label
          end

          if errors
            h[:errors] = errors
          end

          if data
            h[:data] = data
          end

          h
        end

        # @return [Hash] A hash with a root `incremental:` key for the new RFC
        def to_incremental_h
          payload = {
            path: path,
          }
          if label
            payload[:label] = label
          end

          if errors
            payload[:errors] = errors
          else
            payload[:data] = data
          end

          {
            incremental: [payload],
            hasNext: has_next?
          }
        end

        # Create a response chunk compliant with
        # https://www.w3.org/Protocols/rfc1341/7_2_Multipart.html.
        #
        # Meant to support Apollo Client:
        # https://www.apollographql.com/docs/react/features/defer-support.html
        #
        # It appends a final terminator if {#has_next?} is false.
        #
        # @param delimiter [String] preceeds the patch to segment the response
        # @param pretty [Boolean] if true, pretty-print the JSON for debugging
        # @return [String]
        def to_http_multipart(delimiter: "-", pretty: false, first: false, incremental: false)
          data_h = incremental ? to_incremental_h : to_h
          patch = pretty ? JSON.pretty_generate(data_h) : JSON.dump(data_h)
          "#{first ? "\r\n--#{delimiter}" : ""}\r\nContent-Type: application/json\r\nContent-Length: #{patch.bytesize}\r\n\r\n#{patch}\r\n--#{delimiter}#{!has_next? ? "--" : ""}"
        end

        private

        # The result hash is mutable and will be mutated while the query runs.
        # Dup any GraphQL result that you don't want to be modified later.
        def isolate_copy(value)
          if value.is_a?(Hash)
            # Copy hashes because the runtime will be adding to the original hash in-place
            new_value = {}
            value.each do |k, v|
              new_value[k] = isolate_copy(v)
            end
            new_value
          elsif value.is_a?(Array)
            # Even though this array won't be modified
            # make sure nested hashes are copied
            value.map { |v| isolate_copy(v) }
          else
            # Assume it's a scalar value which won't be changed
            value
          end
        end
      end


      # A state manager for deferred data
      class Deferred
        extend Forwardable
        # @return [Array<Deferral>]
        attr_reader :deferrals

        def initialize(context)
          @context = context
          root_deferral = RootDeferral.new(query: context.query)
          @deferrals = [root_deferral]
        end

        def each(&block)
          if block_given?
            @deferrals.each do |deferral|
              case deferral
              when FutureStream::Streamable, Stream::StreamNext::Streamable
                deferral.resolve_each(&block)
              else
                yield(deferral)
              end
            end
          else
            enum_for(:each)
          end
        end

        def map
          if block_given?
            result = []
            each do |def_result|
              result << yield(def_result)
            end
            result
          else
            enum_for(:map)
          end
        end

        # Write an Apollo Client-compatibile stream to a Rails `response`.
        # @see Deferred#to_http_multipart for options
        # @param incremental [Boolean] If true, use the newer "incremental" patch format
        def stream_http_multipart(response, incremental: false, delimiter: "-", pretty: false)
          response.headers["Content-Type"] = "multipart/mixed; boundary=\"#{delimiter}\""
          is_first = true
          each do |deferral|
            patch_str = deferral.to_http_multipart(pretty: pretty, first: is_first, delimiter: delimiter, incremental: (incremental && !is_first))
            is_first &= false
            response.stream.write(patch_str)
          end
        end
      end

      class DeferralNext
        if defined?(GraphQL::Execution::Finalizer)
          include GraphQL::Execution::Finalizer
          include GraphQL::Execution::HaltExecution
        end
        include Serializable

        def initialize(ast_node:, parent_type:, objects:, context:, label:)
          @ast_node = ast_node
          @parent_type = parent_type
          @objects = objects
          @context = context
          @label = label
          @resolved = false
          @data = nil
          @errors = nil
          @graphql_batch_executor = defined?(GraphQL::Batch::Executor) ? GraphQL::Batch::Executor.current : nil
        end

        attr_reader :label, :path

        def finalize_graphql_result(query, result_data, result_key)
          result_data.delete(result_key) # remove the `nil` that was waiting here
        end

        def inspect
          "#<#{self.class.name} @path=#{path.inspect} @ast_node=#{@ast_node.to_query_string.inspect} ...>"
        end

        def has_next?
          resolve
          deferrals = @context[:defer].deferrals
          deferrals.last != self
        end

        def data
          resolve
          @data
        end

        def errors
          resolve
          @errors
        end

        private

        def resolve
          return if @resolved
          if @graphql_batch_executor
            prev_graphql_batch_executor = GraphQL::Batch::Executor.current
            GraphQL::Batch::Executor.current = @graphql_batch_executor
          end
          @resolved = true
          is_single_field = false
          partial_path = path || (raise("Invariant: Tried to resolve `@defer` before GraphQL-Ruby had assigned `.path`. This is a GraphQL-Ruby bug. Deferral: #{inspect}"))
          partial_node = nil
          case @ast_node
          when GraphQL::Language::Nodes::Field
            is_single_field = true
            partial_node = OpenStruct.new(selections: [@ast_node.merge(directives: @ast_node.directives.select { |dn| dn.name != "defer" })])
            partial_path = path[0...-1]
          when Language::Nodes::InlineFragment
            partial_node = @ast_node
          when Language::Nodes::FragmentSpread
            partial_node = @context.query.fragments[@ast_node.name]
          else
            raise ArgumentError, "Wrong @ast_node for `@defer`: #{@ast_node.class} (#{@ast_node.to_query_string.inspect})"
          end


          partial_res = @context.query.run_partials([fragment_node: partial_node, path: partial_path, object: @objects.first || true, type: @parent_type, context: @context.to_h])
          partial_res_h = partial_res.first.to_h
          @data = if partial_res_h["data"]
            if is_single_field
              partial_res_h["data"][path.last]
            else
              partial_res_h["data"]
            end
          else
            nil
          end
          @errors = partial_res_h["errors"]
        ensure
          if prev_graphql_batch_executor
            GraphQL::Batch::Executor.current = prev_graphql_batch_executor
          end
        end
      end

      class Deferral
        include Serializable

        # @return [Array<String, Integer>] The path to this deferred part of the query
        attr_reader :path
        # @return [String, nil] A unique label to identify the deferred payload
        attr_reader :label

        def initialize(path:, block:, context:, label:)
          # This path was a new object created by the runtime,
          # so it doesn't need duping.
          @path = path
          @block = block
          @context = context
          @label = label
          @data = nil
          @errors = nil
          @was_resolved = false
        end

        def to_h
          # Run this now so that `hasNext` will be up-to-date
          resolve
          super
        end

        # If success, the final GraphQL value of this deferred part
        def data
          resolve
          @data
        end

        # If there were any errors, an array of errors. Otherwise, `nil`.
        def errors
          resolve
          @errors
        end

        def has_next?
          deferrals = @context[:defer].deferrals
          deferrals.last != self
        end

        private

        def resolve
          if !@was_resolved
            @was_resolved = true
            prev_error_count = @context.errors.size
            dl = @context.respond_to?(:dataloader) && @context.dataloader
            deferred_result = nil
            call_and_resolve_lazies = ->{
              deferred_result = @block.call
              # It might have returned a lazy value, sync it.
              deferred_result = @context.schema.sync_lazy(deferred_result)
              # It might have returned an Array or Hash with nested lazies, sync them
              resolve_lazies([deferred_result])
            }
            if dl && dl.respond_to?(:run_isolated)
              dl.run_isolated(&call_and_resolve_lazies)
            else
              call_and_resolve_lazies.call
            end
            # Some GraphQL-Ruby versions use response objects that need to be unwrapped
            if deferred_result.respond_to?(:graphql_result_data)
              deferred_result = deferred_result.graphql_result_data
            end
            # Dup the value because, if it has nested patches,
            # they'll be added later to the same hash.
            @data = isolate_copy(deferred_result)
            new_error_count = @context.errors.size
            # Diff the errors against the previous errors; if there are more,
            # they happened during `.call` above.
            if new_error_count > prev_error_count
              own_errors = @context.errors.last(new_error_count - prev_error_count)
              own_errors.each { |e| e.respond_to?(:path=) && e.path.nil? && e.path = @path}
              @errors = own_errors.map(&:to_h)
            end
          end
        end

        if GraphQL::VERSION > "2.5.11"
          # Lazy resolution is now handled by Dataloader#run
          def resolve_lazies(_lazies); end
        else
          case Execution::Interpreter::Resolve.method(:resolve_all).arity
          when 1
            # pre-dataloader, < 1.12
            def resolve_lazies(lazies)
              Execution::Interpreter::Resolve.resolve_all(lazies)
            end
          when 2
            # post-dataloader, 1.12+
            def resolve_lazies(lazies)
              Execution::Interpreter::Resolve.resolve_all(lazies, @context.dataloader)
            end
          else
            raise "Unexpected Resolve.resolve_all arity: #{Execution::Interpreter::Resolve.method(:resolve_all).arity}"
          end
        end
      end

      # Acts like a deferral, but represents the root level response.
      # Make sure to `isolate_copy` data and errors, because they'll
      # continue receiving updates as patches are resolved.
      class RootDeferral < Deferral
        def initialize(query:)
          @query = query
          @context = query.context
        end

        def data
          @data ||= isolate_copy(@query.result["data"])
        end

        def errors
          @errors ||= isolate_copy(@query.result["errors"])
        end

        def to_h
          h = {
            hasNext: has_next?
          }
          if (d = data)
            h[:data] = d
          end

          if (e = errors) && e.any?
            h[:errors] = e
          end
          h
        end

        def execution_result
          @query.result
        end
      end
    end
  end
end
