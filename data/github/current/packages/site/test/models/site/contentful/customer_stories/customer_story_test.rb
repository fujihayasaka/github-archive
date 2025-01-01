# typed: true
# frozen_string_literal: true

require "test_helper"

class Site::Contentful::CustomerStories::CustomerStoryTest < GitHub::TestCase
  setup do
    skip if GitHub.enterprise?
  end

  context "preview stories" do
    test "returns all customer stories including preview stories if include_preview is true" do
      VCR.use_cassette("contentful/customer-stories-all-stories-with-preview-stories") do
        stories = Site::Contentful::CustomerStories::CustomerStory.all(include_preview: true)
        assert_includes stories.first.title, "Example"
      end

      VCR.use_cassette("contentful/customer-stories-all-stories-no-preview-stories") do
        stories = Site::Contentful::CustomerStories::CustomerStory.all

        refute_includes stories.first.title, "Example"
      end
    end
  end

  context ".find" do
    test "returns data from Contentful" do
      VCR.use_cassette("contentful/customer-stories-3m") do
        story = Site::Contentful::CustomerStories::CustomerStory.find("3m")

        assert_equal "3m", story.url
      end
    end

    test "returns nil if story does not exist" do
      VCR.use_cassette("contentful/customer-stories-non-existant-story") do
        story = Site::Contentful::CustomerStories::CustomerStory.find("non-existant-story")

        assert_nil story
      end
    end

    test "returns a preview story if include_preview is true" do
      VCR.use_cassette("contentful/customer-stories-example-preview-true") do
        story = Site::Contentful::CustomerStories::CustomerStory.find("showcase-example", include_preview: true)
        refute_nil story
      end
    end

    test "does not return a preview story if include_preview is false" do
      VCR.use_cassette("contentful/customer-stories-example-preview-false") do
        story = Site::Contentful::CustomerStories::CustomerStory.find("showcase-example", include_preview: false)
        assert_nil story
      end
    end

    test "does not return a preview story if include_preview is not passed in" do
      VCR.use_cassette("contentful/customer-stories-example-preview-undefined") do
        story = Site::Contentful::CustomerStories::CustomerStory.find("showcase-example")
        assert_nil story
      end
    end
  end

  context ".find_stories_by_category" do
    test "returns Enterprise story data filtered by category" do
      VCR.use_cassette("contentful/customer-stories-enterprise-stories") do
        stories = Site::Contentful::CustomerStories::CustomerStory.find_stories_by_category(Site::Contentful::CustomerStories::Categories::ENTERPRISE)
        assert_equal 100, stories.length

        first_story = stories.first

        assert_equal "Enterprise", first_story.categories.first
      end
    end

    test "returns Teams story data filtered by category" do
      VCR.use_cassette("contentful/customer-stories-team-stories") do
        stories = Site::Contentful::CustomerStories::CustomerStory.find_stories_by_category(Site::Contentful::CustomerStories::Categories::TEAM)
        first_story = stories.first

        assert_equal "Team", first_story.categories.first
        assert_equal "Cesium", first_story.title
      end
    end

    test "accepts a limit parameter" do
      VCR.use_cassette("contentful/customer-stories-enterprise-6-stories") do
        stories = Site::Contentful::CustomerStories::CustomerStory.find_stories_by_category(Site::Contentful::CustomerStories::Categories::ENTERPRISE, limit: 6)
        assert_equal 6, stories.length
      end
    end

    test "returns only the fields specified in the fields parameter" do
      VCR.use_cassette("contentful/customer-stories-find-stories-by-category-with-fields") do
        stories = Site::Contentful::CustomerStories::CustomerStory.find_stories_by_category(Site::Contentful::CustomerStories::Categories::ENTERPRISE, limit: 6, fields: %w(url))

        assert_equal stories.map(&:fields).map(&:keys), [[:url]] * 6
      end
    end

    test "accepts filter parameters" do
      VCR.use_cassette("contentful/customer-stories-enterprise-stories-filtered") do
        stories = Site::Contentful::CustomerStories::CustomerStory.find_stories_by_category(
          Site::Contentful::CustomerStories::Categories::ENTERPRISE,
          industry_filters: "Healthcare & Life Sciences",
          regions: "Americas"
        )

        assert_includes stories.first.industry_filters, "Healthcare & Life Sciences"
        assert_includes stories.first.regions, "Americas"
      end
    end
  end

  context ".fetch_body_for" do
    test "returns nil if the customer story does not exist" do
      VCR.use_cassette("contentful/customer-stories-body-for-non-existant-story") do
        assert_nil Site::Contentful::CustomerStories::CustomerStory.fetch_body_for("non-existant-story")
      end
    end

    test "returns the customer story body" do
      customer_story = VCR.use_cassette("contentful/customer-stories-3m") do
        Site::Contentful::CustomerStories::CustomerStory.find("3m")
      end

      VCR.use_cassette("contentful/customer-stories-body-for-3m") do
        assert_equal customer_story.body, Site::Contentful::CustomerStories::CustomerStory.fetch_body_for("3m")
      end
    end
  end

  context ".count" do
    test "returns the number of customer stories" do
      VCR.use_cassette("contentful/customer-stories-count") do
        assert_equal 118, Site::Contentful::CustomerStories::CustomerStory.count
      end
    end

    test "allows filters to be passed in" do
      VCR.use_cassette("contentful/customer-stories-count-with-filters") do
        fields = {
          categories: "Enterprise",
          industry_filters: "Healthcare & Life Sciences",
          regions: "Americas"
        }
        assert_equal 4, Site::Contentful::CustomerStories::CustomerStory.count(fields: fields)
      end
    end
  end

  context "#to_json" do
    test "returns a JSON-like representation for the customer story" do
      customer_story = VCR.use_cassette("contentful/customer-stories-3m") do
        Site::Contentful::CustomerStories::CustomerStory.find("3m")
      end

      json = customer_story.to_json

      assert_equal customer_story.categories, json[:categories]
      assert_equal customer_story.lead, json[:lead]
      assert_equal customer_story.title, json[:title]
      assert_equal customer_story.updated_at.iso8601, json[:updated_at]
      assert_equal customer_story.url, json[:url]

      hero_image_json = json[:hero_image]
      assert_equal customer_story.hero_image.description, hero_image_json[:description]
      assert_equal customer_story.hero_image.url, hero_image_json[:url]
      assert_equal customer_story.hero_image.absolute_url, hero_image_json[:absolute_url]

      logo_json = json[:logo]
      assert_equal customer_story.logo.url, logo_json[:url]
      assert_equal customer_story.logo.absolute_url, logo_json[:absolute_url]

      # empty for this customer story
      # TODO: find a customer_story with these fields populated
      assert_empty json[:related_stories]
      assert_nil json[:video_desc]
      assert_nil json[:video_src]
    end
  end
end
