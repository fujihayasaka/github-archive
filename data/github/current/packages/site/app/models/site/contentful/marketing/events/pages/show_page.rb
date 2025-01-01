# typed: true
# frozen_string_literal: true

class Site::Contentful::Marketing::Events::Pages::ShowPage < Site::Contentful::Page
  def initialize(slug:)
    @slug = slug.downcase
  end

  def cache_key
    "site.contentful.marketing.events.pages.show.#{@slug}/v1"
  end

  def fetch_data_from_contentful
    event = Site::Contentful::Marketing::Events::Event.find(@slug)

    return { event: nil } if event.blank?

    { event: event.to_json }
  end
end
