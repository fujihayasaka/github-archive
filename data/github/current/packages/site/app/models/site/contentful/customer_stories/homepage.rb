# typed: true
# frozen_string_literal: true

require "contentful"

class Site::Contentful::CustomerStories::Homepage < Site::Contentful::Entry
  include Site::Contentful::CustomerStories::Client, Site::Contentful::Query

  def self.content_type
    "pageIndexPage"
  end

  def self.content
    query(limit: 1, include: 4).first
  end

  def to_json
    {
      heading: heading,
      link_text: link_text,
      enterprise_stories_heading: enterprise_stories_heading,
      team_stories_heading: team_stories_heading,
      subheading: subheading,
      details: details,
      callouts: Array(callouts).map { |callout| { label: callout.label, value: callout.value } },
      highlighted_story: highlighted_story.to_json,
      featured_stories: Array(featured_stories).map(&:preview_json),
      featured_logos: Array(featured_logos).map(&:to_json),
      featured_testimonials: Array(featured_testimonials).map(&:to_json),
    }
  end
end
