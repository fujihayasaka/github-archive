# typed: true
# frozen_string_literal: true

module Api::App::PaginationDependency
  extend T::Sig
  extend T::Helpers

  requires_ancestor { Api::App }

  sig do
    params(
      collection_size: T.nilable(Numeric),
      skip_last_page_link: T.nilable(T::Boolean)
    )
    .void
  end
  def set_pagination_headers(collection_size: nil, skip_last_page_link: false)
    paginator.collection_size ||= collection_size
    return if paginator.collection_size.nil? || paginator.collection_size.zero?

    if paginator.previous?
      @links.add_current({ page: paginator.previous_page }, rel: "prev")
    end

    if paginator.next?
      @links.add_current({ page: paginator.next_page }, rel: "next")
    end

    if paginator.page != paginator.last_page && !skip_last_page_link
      @links.add_current({ page: paginator.last_page }, rel: "last")
    end

    if paginator.page != paginator.first_page
      @links.add_current({ page: paginator.first_page }, rel: "first")
    end
  end
end
