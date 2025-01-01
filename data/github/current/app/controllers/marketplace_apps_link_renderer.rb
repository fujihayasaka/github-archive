# typed: true
# frozen_string_literal: true

class MarketplaceAppsLinkRenderer < WillPaginate::ActionView::LinkRenderer
  PAGE_PARAM = :marketplace_apps_page

  def url(page)
    "?#{PAGE_PARAM}=#{page}"
  end
end
