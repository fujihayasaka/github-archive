# typed: true
# frozen_string_literal: true

class Site::Contentful::Marketing::Events::Pages::IndexPage < Site::Contentful::Page
  def cache_key
    "site.contentful.marketing.events.pages.index/v1"
  end

  def fetch_data_from_contentful
    page_data = Site::Contentful::Marketing::Page.find("events")

    active_events = Site::Contentful::Marketing::Events::Event.active
    persistent_events = Site::Contentful::Marketing::Events::Event.persistent
    sponsored_events = Site::Contentful::Marketing::Events::Event.sponsored

    {
      events: [active_events, persistent_events].flatten(1).sort_by(&:start_date).reverse.map(&:to_json),
      sponsored_events: sponsored_events.map(&:to_json),
      page_data: page_data_to_json(page_data)
    }
  end

  def page_data_to_json(page_data)
    {
      title: page_data.title,
      seo_description: page_data.seo.description,
      seo_image_url: page_data.seo.image.url,
      heading: page_data.content.heading,
      subheading: page_data.content.subheading,
    }
  end
end
