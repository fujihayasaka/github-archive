# typed: true
# frozen_string_literal: true

class Site::Contentful::Marketing::OpenSource::Pages::IndexPage < Site::Contentful::Page
  def cache_key
    "site.contentful.marketing.open_source.pages.index/v1"
  end

  def fetch_data_from_contentful
    stories = Site::Contentful::Readme::DeveloperStory.all(include_unpublished: false, limit: 4)

    {
      stories: stories.map(&:to_json)
    }
  end
end
