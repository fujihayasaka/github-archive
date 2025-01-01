# typed: true
# frozen_string_literal: true

class Site::Contentful::Marketing::OpenSource::Pages::IndexPage < Site::Contentful::Page
  sig { override.returns(String) }
  def cache_key
    "site.swp.open_source.index"
  end

  sig { override.returns(JsonLikeType) }
  def fetch_data_from_contentful
    stories = Site::Contentful::Readme::DeveloperStory.all(include_unpublished: false, limit: 4)

    {
      stories: stories.map(&:to_json)
    }
  end
end
