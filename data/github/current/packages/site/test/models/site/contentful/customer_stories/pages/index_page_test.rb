# typed: true
# frozen_string_literal: true

require "test_helper"

class Site::Contentful::CustomerStories::Pages::IndexPageTest < GitHub::TestCase
  require_cassettes_for_external_http_connections

  setup do
    skip if GitHub.enterprise?
    Site::Contentful::CustomerStories::Pages::IndexPage.any_instance.stubs(:random_order).returns(nil)
    Site::Contentful::CustomerStories::Pages::IndexPage.any_instance.stubs(:random_enterprise_filter).returns({})

    @homepage = VCR.use_cassette("contentful/customer-stories-homepage-content") do
      Site::Contentful::CustomerStories::Homepage.content
    end

    @enterprise_stories = VCR.use_cassette("contentful/customer-stories-enterprise-stories") do
      Site::Contentful::CustomerStories::CustomerStory.find_stories_by_category(Site::Contentful::CustomerStories::Categories::ENTERPRISE)
    end

    @team_stories = VCR.use_cassette("contentful/customer-stories-team-stories") do
      Site::Contentful::CustomerStories::CustomerStory.find_stories_by_category(Site::Contentful::CustomerStories::Categories::TEAM)
    end

    @index_page_for_non_staff = Site::Contentful::CustomerStories::Pages::IndexPage.new
  end

  context "#fetch_data_from_contentful" do
    test "returns page data and stories" do
      VCR.use_cassette("contentful/customer-stories-index-page") do
        result = @index_page_for_non_staff.fetch_data_from_contentful
        team_stories = @team_stories.take(Site::Contentful::CustomerStories::Pages::IndexPage::NUMBER_OF_STORIES_TO_DISPLAY).map(&:preview_json)
        enterprise_stories = @enterprise_stories.take(Site::Contentful::CustomerStories::Pages::IndexPage::NUMBER_OF_STORIES_TO_DISPLAY).map(&:preview_json)

        assert_equal @homepage.to_json, result[:homepage]
        assert_equal team_stories, result[:team_stories]
        assert_equal enterprise_stories, result[:enterprise_stories]
      end
    end
  end

  context "#cache_key" do
    test "builds the right cache key" do
      assert_equal "site.swp.customer_stories.index.staff:false", @index_page_for_non_staff.cache_key

      index_page_for_staff = Site::Contentful::CustomerStories::Pages::IndexPage.new(for_staff: true)

      assert_equal "site.swp.customer_stories.index.staff:true", index_page_for_staff.cache_key
    end

    test "supports version 2 cache key" do
      page = Site::Contentful::CustomerStories::Pages::IndexPage.new(for_staff: false, cache_version: :v2)

      assert_equal "site.contentful.customer_stories.pages.index.v2.for_staff:false", page.cache_key
    end
  end

  context "#stale?" do
    test "true if the page hasn't been revalidated in the last hour" do
      Timecop.freeze(2.hours.ago) do
        VCR.use_cassette("contentful/customer-stories-index-page") do
          page = Site::Contentful::CustomerStories::Pages::IndexPage.new(for_staff: false, cache_version: :v2)
          page.revalidate
        end
      end

      page = Site::Contentful::CustomerStories::Pages::IndexPage.new(for_staff: false, cache_version: :v2)
      assert page.stale?
    end

    test "false if the page has been revalidated in the last hour" do
      Timecop.freeze(30.minutes.ago) do
        VCR.use_cassette("contentful/customer-stories-index-page") do
          page = Site::Contentful::CustomerStories::Pages::IndexPage.new(for_staff: false, cache_version: :v2)
          page.revalidate
        end
      end

      page = Site::Contentful::CustomerStories::Pages::IndexPage.new(for_staff: false, cache_version: :v2)
      refute page.stale?
    end
  end

  context "#updated_at" do
    test "set to now when fetching data from contentful and using cache_version :v2" do
      page = Site::Contentful::CustomerStories::Pages::IndexPage.new(for_staff: false, cache_version: :v2)

      VCR.use_cassette("contentful/customer-stories-index-page") do
        page.revalidate
      end

      assert T.must(page.updated_at) > 1.minute.ago
    end

    test "no updated at is set if using cache_version :v1" do
      page = Site::Contentful::CustomerStories::Pages::IndexPage.new(for_staff: false, cache_version: :v1)

      VCR.use_cassette("contentful/customer-stories-index-page") do
        page.revalidate
      end

      assert_nil page.updated_at
    end
  end

  context "#revalidate_if_stale" do
    test "enqueues revalidation job if the page is stale" do
      Timecop.freeze(2.hours.ago) do
        VCR.use_cassette("contentful/customer-stories-index-page") do
          page = Site::Contentful::CustomerStories::Pages::IndexPage.new(for_staff: false, cache_version: :v2)
          page.revalidate
        end
      end

      page = Site::Contentful::CustomerStories::Pages::IndexPage.new(for_staff: false, cache_version: :v2)

      job_args = [
        Site::Contentful::CustomerStories::Pages::IndexPage,
        { for_staff: false, cache_version: :v2 }
      ]

      assert_enqueued_with(job: RevalidatePageJob, args: job_args) do
        page.revalidate_if_stale
      end
    end

    test "doesn't enqueue a revalidation job if the page is not stale" do
      Timecop.freeze(30.minutes.ago) do
        VCR.use_cassette("contentful/customer-stories-index-page") do
          page = Site::Contentful::CustomerStories::Pages::IndexPage.new(for_staff: false, cache_version: :v2)
          page.revalidate
        end
      end

      page = Site::Contentful::CustomerStories::Pages::IndexPage.new(for_staff: false, cache_version: :v2)

      assert_no_enqueued_jobs do
        page.revalidate_if_stale
      end
    end
  end
end
