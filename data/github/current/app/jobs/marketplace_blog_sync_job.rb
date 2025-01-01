# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class MarketplaceBlogSyncJob < ApplicationJob
  queue_as :marketplace
  schedule interval: 24.hours, condition: -> { !GitHub.enterprise? }

  MAX_PER_PAGE = 10
  GITHUB_BLOG_MARKETPLACE_FEED = "https://github.blog/category/uncategorized/marketplace/feed/"

  def perform
    more_pages = T.let(true, T::Boolean)
    current_page = 1

    while more_pages
      params = {}
      if current_page > 1
        params[:paged] = current_page
      end

      response = faraday.get(GITHUB_BLOG_MARKETPLACE_FEED, params)
      doc = Nokogiri::XML(response.body)
      feed = doc.xpath("//channel/item")

      break unless feed.any?

      more_pages = feed.length == MAX_PER_PAGE
      current_page += 1

      feed.each do |rss_item|
        with_write { Marketplace::Story.update_or_create_from_rss_feed(rss_item) }
      end
    end
  end

  private

  def faraday
    GitHub::FaradayClient::External.new do |c|
      c.adapter Faraday.default_adapter
    end
  end
end
