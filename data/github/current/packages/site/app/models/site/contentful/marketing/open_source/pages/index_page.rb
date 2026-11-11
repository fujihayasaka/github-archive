# typed: true
# frozen_string_literal: true

class Site::Contentful::Marketing::OpenSource::Pages::IndexPage < Site::Contentful::Page
  sig { override.returns(T.any(String, Site::Contentful::Page::CacheKey)) }
  def cache_key
    if FeatureFlag.vexi.enabled?(:swp_safe_cache_keys, default: false)
      Site::Contentful::Page::CacheKey.new(
        base: "site.swp",
        locale: "en",
        path: "/open-source",
        version: 2
      )
    else
      "site.swp.open_source.index"
    end
  end

  sig { override.returns(JsonLikeType) }
  def fetch_data_from_contentful
    stories = Site::Contentful::Readme::DeveloperStory.all(include_unpublished: false, limit: 4)

    {
      stories: stories.map(&:to_json)
    }
  end
end
