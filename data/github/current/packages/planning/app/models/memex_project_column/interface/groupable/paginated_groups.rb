# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Groupable
  class PaginatedGroups
    include GitHub::Memoizer

    AfterKey = T.type_alias { T::Hash[String, T.untyped] }

    sig { returns(T::Array[Group]) }
    attr_reader :nodes

    delegate :has_next_page, :has_previous_page, to: :@page_info

    sig do
      params(
        nodes: T::Array[Group],
        has_previous_page: T::Boolean,
        has_next_page: T::Boolean,
        after_key: T.nilable(AfterKey)
      )
      .void
    end
    def initialize(nodes: [], has_previous_page: false, has_next_page: false, after_key: nil)
      @after_key = after_key
      @nodes = nodes
      @page_info = T.let(
        Search::Responses::PageInfo.new(has_previous_page:, has_next_page:, start_cursor:, end_cursor:),
        Search::Responses::PageInfo
      )
    end

    sig { returns(T.nilable(String)) }
    def start_cursor; end

    sig { returns(T.nilable(String)) }
    memoize def end_cursor
      Search::Responses::PropertyEncoder.encode(@after_key)
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_hash
      {
        nodes: @nodes.map(&:to_hash),
        page_info: @page_info.to_hash
      }
    end
  end
end
