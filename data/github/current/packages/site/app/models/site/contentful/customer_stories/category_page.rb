# typed: true
# frozen_string_literal: true

require "contentful"

class Site::Contentful::CustomerStories::CategoryPage < Site::Contentful::Entry
  include Site::Contentful::CustomerStories::Client, Site::Contentful::Query

  def self.content_type
    "categoryPage"
  end

  def self.content(category)
    query(fields: { category_name: category.titleize }, limit: 1).first
  end

  def to_json
    {
      category_name: category_name,
      heading: heading,
      tagline: tagline,
      card_links: card_links,
      featured_stories: Array(featured_stories).map(&:preview_json),
    }
  end
end
