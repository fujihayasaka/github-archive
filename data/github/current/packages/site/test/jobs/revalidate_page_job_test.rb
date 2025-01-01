# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class RevalidatePageJobTest < GitHub::TestCase
  include JobTestHelper
  require_cassettes_for_external_http_connections

  unless GitHub.enterprise?
    test "revalidates a page" do
      index_page_for_staff = Site::Contentful::Readme::Pages::Topics::IndexPage.new(for_readme_staff: true)

      # We save some data in the cache for this page so we can verify it gets revalidated later.
      data = Zlib::Deflate.deflate(JSON.generate({ navigation_topics: [], topics_with_stories: [] }))
      GitHub.kv.set(index_page_for_staff.cache_key, data)

      VCR.use_cassette("contentful/revalidate-page-job-test") do
        Timecop.freeze(Time.utc(2022, 6, 13)) do
          RevalidatePageJob.perform_now(Site::Contentful::Readme::Pages::Topics::IndexPage, for_readme_staff: true)

          # We directly access the cache to verify it has been revalidated.
          cached_data = Zlib::Inflate.inflate(GitHub.kv.get(index_page_for_staff.cache_key).value { nil })
          parsed_data = JSON.parse(cached_data, symbolize_names: true)

          assert_equal(4, parsed_data[:topics_with_stories].count)
          assert_equal(4, parsed_data[:navigation_topics].count)
        end
      end
    end

    test "will lock the job if it is already running with the same arguments" do
      assert_enqueued_jobs 1 do
        RevalidatePageJob.perform_later(Site::Contentful::Readme::Pages::Topics::IndexPage, for_readme_staff: true)
        RevalidatePageJob.perform_later(Site::Contentful::Readme::Pages::Topics::IndexPage, for_readme_staff: true)
      end
    end

    test "jobs with different arguments will not be locked" do
      assert_enqueued_jobs 2 do
        RevalidatePageJob.perform_later(Site::Contentful::Readme::Pages::Topics::IndexPage, for_readme_staff: true)
        RevalidatePageJob.perform_later(Site::Contentful::Readme::Pages::Topics::IndexPage, for_readme_staff: false)
      end
    end
  end
end
