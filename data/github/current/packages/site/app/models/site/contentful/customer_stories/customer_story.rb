# typed: true
# frozen_string_literal: true

require "contentful"

class Site::Contentful::CustomerStories::CustomerStory < Site::Contentful::Entry
  include Site::Contentful::CustomerStories::Client, Site::Contentful::Query

  def self.content_type
    "story"
  end

  def self.sparse_fields_for_index
    %w(url title lead videoSrc heroImage industryFilters regions previewStory productFilters)
  end

  ORDERED_STORY_PRODUCTS = {
    ACTIONS: "GitHub Actions",
    CODESPACES: "GitHub Codespaces",
    COPILOT: "GitHub Copilot",
    DISCUSSIONS: "GitHub Discussions",
    ENTERPRISE: "GitHub Enterprise",
    ISSUES: "GitHub Issues",
    PACKAGES: "GitHub Packages",
    SECURITY: "GitHub Advanced Security",
    SERVICES: "GitHub Expert Services",
    TEAM: "GitHub Team",
  }

  def self.find(slug, include_preview: false)
    query(fields: {
      url: slug.downcase,
      preview_story: include_preview ? %w[true false] : %w[false]
    }, limit: 1).first
  end

  def self.all(limit: nil, include_preview: false)
    query(fields: { preview_story: include_preview ? %w[true false] : %w[false] }, limit: limit)
  end

  def self.find_stories_by_category(category, limit: nil, fields: nil, industry_filters: nil, regions: nil, product_filters: nil, size: nil, order: nil, include_preview: false)
    query_fields = {
      categories: category,
      preview_story: include_preview ? %w[true false] : %w[false],
      industry_filters: industry_filters,
      regions: regions,
      product_filters: product_filters,
      size: size,
    }.compact

    query(fields: query_fields, limit: limit, select: fields, order: order)
  end

  def self.fetch_body_for(slug)
    query(fields: { url: slug.downcase }, limit: 1, select: :body).first&.body
  end

  def self.count(fields: {})
    query(select: "sys.id", limit: 1000, fields: fields).count
  end

  def main_category
    if categories&.include?(Site::Contentful::CustomerStories::Categories::ENTERPRISE)
      Site::Contentful::CustomerStories::Categories::ENTERPRISE
    elsif categories&.include?(Site::Contentful::CustomerStories::Categories::TEAM)
      Site::Contentful::CustomerStories::Categories::TEAM
    else
      categories&.first
    end
  end

  def to_json
    {
      callouts: Array(callouts).map { |callout| { label: callout.label, value: callout.value } },
      categories: categories,
      main_category: main_category,
      facts: Array(facts).map { |fact| { label: fact.fact_name, value: fact.fact_value } },
      related_stories: Array(related_stories).map(&:preview_json),
      hero_image: hero_image.to_json,
      highlights: Array(highlights).map { |highlight| { name: highlight.name, value: highlight.value } },
      product_filters: product_filters,
      lead: lead,
      logo: logo&.to_json,
      title: title,
      keep_logo_color: keep_logo_color,
      updated_at: updated_at.iso8601,
      url: url,
      video_desc: video_desc,
      video_src: video_src,
      preview_story: preview_story
    }
  end

  def preview_json
    {
      url: url,
      title: title,
      logo: logo&.to_json,
      keep_logo_color: keep_logo_color,
      hero_image_url: hero_image&.url,
      video_src: video_src,
      lead: lead,
      industry_filters: Array(industry_filters).map(&:parameterize),
      regions: Array(regions).map(&:parameterize),
      product_filters: product_filters,
      preview_story: preview_story
    }.compact
  end
end
