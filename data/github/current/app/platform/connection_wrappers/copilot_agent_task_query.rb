# typed: strict
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    # This class knows how to speak GraphQL connection language (cursors, page info, edges,
    # nodes, first, last, after, before, etc.) and convert those values to offset-based pagination values and
    # domain-modeled sort values and ultimately call the underlying domain model to fetch the data.
    class CopilotAgentTaskQuery < ConnectionWrappers::Base
      include Offsettable
      include GitHub::Memoizer

      class PrecomputedEdge < T::Struct
        const :node, CopilotSessions::Task
        const :cursor, String
      end

      sig { returns(User) }
      attr_reader :user

      sig { returns(Copilot::DecryptedToken) }
      attr_reader :token

      sig { returns(Integer) }
      attr_reader :limit

      sig { returns(Integer) }
      attr_reader :offset

      sig { returns(Integer) }
      attr_reader :page

      sig { returns(T.nilable(String)) }
      attr_reader :order_by_field

      sig { returns(T.nilable(String)) }
      attr_reader :order_by_direction

      sig { returns(T.nilable(T::Array[String])) }
      attr_reader :filter_by_session_states

      delegate :tasks, :has_next_page, to: :task_list

      sig do
        params(
          user: User,
          token: Copilot::DecryptedToken,
          max_page_size: Integer,
          first: T.nilable(Integer),
          last: T.nilable(Integer),
          after: T.nilable(String),
          before: T.nilable(String),
          order_by: T.nilable(T.any(T::Hash[Symbol, String], Inputs::CopilotAgentTaskOrder)),
          filter_by: T.nilable(T.any(T::Hash[Symbol, String], Inputs::CopilotAgentTaskFilter)),
          field: T.nilable(Platform::Objects::Base::Field)
        ).void
      end
      def initialize(
        user:,
        token:,
        max_page_size: 100,
        first: nil,
        last: nil,
        after: nil,
        before: nil,
        order_by: nil,
        filter_by: nil,
        field: nil
      )
        @user = user
        @token = token
        @order_by_field = T.let(order_by&.dig(:field), T.nilable(String))
        @order_by_direction = T.let(order_by&.dig(:direction), T.nilable(String))

        @limit = T.let(determine_limit(max_page_size, first, last), Integer)
        @offset = T.let(determine_offset(last, before, after, field), Integer)
        @page = T.let(determine_page(limit, @offset), Integer)

        @filter_by_session_states = T.let(filter_by&.dig(:states), T.nilable(T::Array[String]))

        super(
          nil,
          first:,
          last:,
          after:,
          before:,
          max_page_size:
        )
      end

      sig { returns(T::Array[PrecomputedEdge]) }
      def edges
        tasks.each_with_index.map do |node, index|
          cursor = CursorGenerator.generate_cursor(offset + index)

          PrecomputedEdge.new(node:, cursor:)
        end
      end

      sig { returns(T::Array[CopilotSessions::Task]) }
      def edge_nodes
        edges.map(&:node)
      end

      sig { returns(PageInfo) }
      def page_info
        PageInfo.new(
          has_next_page:,
          has_previous_page:,
          start_cursor: determine_start_cursor(offset),
          end_cursor: determine_end_cursor(limit, offset),
        )
      end

      private

      # This is the main method that makes the call to CAPI and returns a response object.
      # Memoize this because we do not want to call the underlying API more than once.
      sig { returns(CopilotSessions::TaskList) }
      memoize def task_list
        entry_point = :agent_tasks_for_user_via_graphql

        CopilotSessions::TaskList.for_user(
          user:,
          entry_point:,
          token:,
          page_size: limit,
          page_number: page,
          sort_field:,
          sort_direction:,
          session_states:
        )
      end

      sig { returns(T::Boolean) }
      def has_previous_page
        offset > 0
      end

      sig { returns(T.nilable(CopilotSessions::TaskSortField)) }
      def sort_field
        return nil unless order_by_field

        CopilotSessions::TaskSortField.deserialize(T.must(order_by_field).downcase)
      end

      sig { returns(T.nilable(CopilotSessions::SortDirection)) }
      def sort_direction
        return nil unless order_by_direction

        CopilotSessions::SortDirection.deserialize(T.must(order_by_direction).downcase)
      end

      sig { returns(T.nilable(T::Array[CopilotSessions::SessionState])) }
      def session_states
        return nil unless filter_by_session_states

        T.must(filter_by_session_states).map do |session_state|
          CopilotSessions::SessionState.deserialize(session_state.downcase)
        end
      end
    end
  end
end
