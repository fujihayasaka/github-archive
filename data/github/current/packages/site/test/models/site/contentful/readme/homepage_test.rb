# typed: true
# frozen_string_literal: true

require "test_helper"

class Site::Contentful::Readme::HomepageTest < GitHub::TestCase
  setup do
    skip if GitHub.enterprise?

    @homepage = VCR.use_cassette("contentful/readme-homepage") do
      Site::Contentful::Readme::Homepage.latest(include_unpublished: true)
    end
  end

  test "#featured_slugs" do
    expected_slugs = %w[open-source-accessibility rohan-gupta open-source-machine-learning staff-engineers shopify-github-projects accessible-software-development hubspot-github-copilot css-future comaintaining-openness improve-productivity-automation]

    assert_same_elements expected_slugs, @homepage.featured_slugs
    assert_equal @homepage.featured_slugs.count, 10
  end

  test "#published?" do
    Timecop.freeze("2021-05-01T12:00".in_time_zone("Pacific Time (US & Canada)")) do
      @homepage.stubs(:publication_date).returns(DateTime.parse("2021-05-01T08:00:00+00:00"))
      assert @homepage.published?

      @homepage.stubs(:publication_date).returns(DateTime.parse("2021-05-01T16:00:00+00:00"))
      refute @homepage.published?
    end
  end

  context ".fetch_by_id" do
    test "returns nil if the entry is not found" do
      VCR.use_cassette("contentful/readme/models/homepage/fetch_by_id_not_found") do
        assert_nil Site::Contentful::Readme::Homepage.fetch_by_id("not_found")
      end
    end

    test "returns the homepage if it exists" do
      VCR.use_cassette("contentful/readme/models/homepage/fetch_by_id") do
        assert_instance_of Site::Contentful::Readme::Homepage, Site::Contentful::Readme::Homepage.fetch_by_id(@homepage.id)
      end
    end
  end
end
