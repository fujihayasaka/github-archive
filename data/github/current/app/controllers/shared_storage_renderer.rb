# typed: true
# frozen_string_literal: true

class SharedStorageRenderer < WillPaginate::ActionView::LinkRenderer
  PAGE_PARAM = :shared_storage_page

  def url(page)
    "?#{PAGE_PARAM}=#{page}"
  end
end
