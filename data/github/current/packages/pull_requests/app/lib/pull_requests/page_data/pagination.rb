# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Pagination
  class PageInfo < T::Struct
    const :has_next_page, T::Boolean
    const :cursor, T.nilable(String)
    const :page, Integer

    sig { params(page: Integer).returns(PageInfo) }
    def self.empty(page: 1)
      new(
        has_next_page: false,
        cursor: nil,
        page: page
      )
    end
  end

  # Consumers can use this directly with T.untyped items, or create their own
  # typed subclass/wrapper for stronger type safety.
  class PaginatedResult < T::Struct
    const :items, T::Array[T.untyped]
    const :page_info, PageInfo

    sig { params(page: Integer).returns(PaginatedResult) }
    def self.empty(page: 1)
      new(
        items: [],
        page_info: PageInfo.empty(page: page)
      )
    end
  end

  # Helper module for setting Link headers in controllers
  # The header is read by clients to perform cursor-based pagination
  module LinkHeader
    sig { params(page_info: PageInfo, request_path: String).returns(T.nilable(String)) }
    def self.build_next_link(page_info:, request_path:)
      return nil unless page_info.has_next_page && page_info.cursor

      next_page = page_info.page + 1
      next_url = "#{request_path}?after=#{page_info.cursor}&page=#{next_page}"
      %(<#{next_url}>; rel="next")
    end

    sig { params(response: ActionDispatch::Response, page_info: PageInfo, request_path: String).void }
    def self.set_link_header(response:, page_info:, request_path:)
      link = build_next_link(page_info: page_info, request_path: request_path)
      response.set_header("Link", link) if link
    end
  end
end
