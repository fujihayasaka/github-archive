# typed: strict
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    class CopilotAgentTaskWrapper < ConnectionWrappers::Base
      include Offsettable
      include GitHub::Memoizer

      class PrecomputedEdge < T::Struct
        const :node, CopilotSessions::TaskApi::Task
        const :cursor, String
      end

      sig { returns(Integer) }
      attr_reader :limit

      sig { returns(Integer) }
      attr_reader :offset

      sig { returns(Integer) }
      attr_reader :page

      delegate :tasks, :has_next_page, to: :task_list

      sig { returns(CopilotAgentTaskWrapper) }
      def self.empty
        new(fetcher: ->(_page, _limit) { CopilotSessions::TaskApi::TaskList.new(tasks: [], has_next_page: false) })
      end

      sig do
        params(
          fetcher: T.proc.params(page: Integer, limit: Integer).returns(CopilotSessions::TaskApi::TaskList),
          first: T.nilable(Integer),
          last: T.nilable(Integer),
          after: T.nilable(String),
          before: T.nilable(String),
          max_page_size: Integer,
          field: T.nilable(Platform::Objects::Base::Field)
        ).void
      end
      def initialize(
        fetcher:,
        first: nil,
        last: nil,
        after: nil,
        before: nil,
        max_page_size: 100,
        field: nil
      )
        @fetcher = fetcher

        @limit = T.let(determine_limit(max_page_size, first, last), Integer)
        @offset = T.let(determine_offset(last, before, after, field), Integer)
        @page = T.let(determine_page(limit, @offset), Integer)

        super(
          nil,
          first:,
          last:,
          after:,
          before:,
          max_page_size:,
        )
      end

      sig { returns(T::Array[PrecomputedEdge]) }
      def edges
        tasks.each_with_index.map do |node, index|
          cursor = CursorGenerator.generate_cursor(offset + index)

          PrecomputedEdge.new(node:, cursor:)
        end
      end

      sig { returns(T::Array[T.untyped]) }
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

      sig { returns(CopilotSessions::TaskApi::TaskList) }
      memoize def task_list
        @fetcher.call(page, limit)
      end

      sig { returns(T::Boolean) }
      def has_previous_page
        offset > 0
      end
    end
  end
end
