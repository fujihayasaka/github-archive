# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::PublishedWiki < FeedItem
    def repository
      subject[:repository]
    end

    def updates
      subject[:updates]
    end

    def pages_payload
      updates.map do |page_hash|
        {
          action: page_hash["action"],
          sha: page_hash["sha"],
          page: find_page(page_hash),
        }
      end
    end

    def api_type
      "GollumEvent"
    end

    def payload
      {
        pages: pages_payload.map do |hash|
          {
            page_name: hash[:page]&.name,
            title: hash[:page]&.title,
            summary: hash[:page]&.summary,
            action: hash[:action],
            sha: hash[:sha],
            html_url: url(hash[:page]),
          }
        end
      }
    end

    def self.supports_graphql?
      false
    end

    # Analytics not required since this is not shown in the Feed
    def analytics_card_type
      nil
    end

    private

    def find_page(page_hash)
      repository.unsullied_wiki.pages.find(page_hash["name"], page_hash["sha"]) ||
        repository.unsullied_wiki.pages.find(page_hash["name"])
    end

    def url(page)
      return "/" unless repository && page

      "%s/wiki/%s" % [
        repository.permalink(include_host: false),
        u(GitHub::Unsullied::Page.cname(page.name))]
    end

    # Escapes a URL fragment, allowing only "/"'s
    #
    # s - The String fragment to escape.
    #
    # Returns an escaped String.
    def u(s)
      return "" if s.blank?
      CGI.escape(s).gsub /%2F/, "/"
    end
  end
end
