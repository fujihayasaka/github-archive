# typed: true
# frozen_string_literal: true

require "test_helper"

class Site::Contentful::CustomerStories::HomepageTest < GitHub::TestCase
  setup do
    @homepage = VCR.use_cassette("contentful/customer-stories-homepage-content") do
      Site::Contentful::CustomerStories::Homepage.content
    end
  end

  test "returns data from Contentful" do
    assert_equal 3, @homepage.featured_stories.count
    assert @homepage.heading
  end

  test "serializes to JSON" do
    json = @homepage.to_json

    assert_equal @homepage.heading, json[:heading]
    assert_equal @homepage.link_text, json[:link_text]
    assert_equal @homepage.enterprise_stories_heading, json[:enterprise_stories_heading]
    assert_equal @homepage.team_stories_heading, json[:team_stories_heading]
    assert_equal @homepage.subheading, json[:subheading]
    assert_equal @homepage.details, json[:details]
    @homepage.callouts.each do |callout|
      assert_includes json[:callouts], { label: callout.label, value: callout.value }
    end
    assert_equal @homepage.highlighted_story.to_json, json[:highlighted_story]
    assert_equal @homepage.featured_stories.map(&:preview_json), json[:featured_stories]
    assert_equal @homepage.featured_logos.map(&:to_json), json[:featured_logos]
    assert_equal @homepage.featured_testimonials.map(&:to_json), json[:featured_testimonials]
  end
end
