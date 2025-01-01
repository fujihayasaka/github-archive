# typed: true
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    class ExperimentRelation < ConnectionWrappers::Base
      def initialize(*args, **kwargs)
        super
        create_experiment_connections!
      end

      # Public: Generate a cursor from an ActiveRecord object
      #
      # item - An ActiveRecord::Base instance (or Promise that resolves to one)
      #
      # Returns a Promise that resolves to a String cursor value
      def cursor_for(item)
        control_connection.cursor_for(item)
      end

      def edge_nodes
        return @edge_nodes if defined?(@edge_nodes)

        @edge_nodes = control_connection.edge_nodes
      end

      def page_info
        control_connection.page_info
      end

      # Zero out the expected results. Used in situations where the API AuthZ
      # check failed, and the resolvers are still expecting data to come through.
      # They should receive nothing, though.
      def none
        @edge_nodes = ::Promise.all([])
        self
      end

      def has_next_page
        control_connection.has_next_page
      end

      def has_previous_page
        control_connection.has_previous_page
      end

      def total_count
        control_connection.total_count
      end

      private

      # The validation happens during Object initialization.
      def create_experiment_connections!
        Scientist.run "#{@items.name}-results" do |e|
          e.use { connection_results(control_connection) }
          e.try { connection_results(candidate_connection) }
          e.run_if { @items.run_if.call }
          e.ignore { @items.ignore.call }
          e.context(@items.context) if @items.context
          e.compare { |control, candidate| @items.compare.call(control, candidate) } if @items.compare
          e.clean { |value| @items.clean.call(value) } if @items.clean
        end
      end

      def control_connection
        return @control_connection if defined?(@control_connection)
        @control_connection = create_relation_connection_wrapper(@items.control.call)
      end

      def candidate_connection
        return @candidate_connection if defined?(@candidate_connection)
        @candidate_connection = create_relation_connection_wrapper(@items.candidate.call)
      end

      def connection_results(connection)
        return connection.nodes if connection.is_a?(Platform::ConnectionWrappers::ArrayWrapper)
        connection.send(:results)
      end

      def create_relation_connection_wrapper(relation)
        connection_arguments = {
          first: @first_value,
          last: @last_value,
          before: @before_value,
          after: @after_value,
          arguments: @arguments,
          field: @field,
          parent: @parent,
          context: @context,
          max_page_size: @max_page_size
        }
        return RemoteRelation.new(relation, **connection_arguments) if relation.is_a?(Platform::Wrappers::RemoteProxyRelation)
        return ArrayWrapper.new(relation, **connection_arguments) if relation.is_a?(Array)
        return CursorCollection.new(relation, **connection_arguments) if relation.is_a?(GH::Domain::CursorCollection)

        Relation.new(relation, **connection_arguments)
      end
    end
  end
end
