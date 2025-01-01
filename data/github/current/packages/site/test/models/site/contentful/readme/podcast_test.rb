# typed: true
# frozen_string_literal: true

require "test_helper"

class Site::Contentful::Readme::PodcastTest < GitHub::TestCase
  require_cassettes_for_external_http_connections

  unless GitHub.enterprise?
    setup do
      @podcast_evan = VCR.use_cassette("contentful/readme-podcast-growing-vue") do
        Site::Contentful::Readme::Podcast.find("growing-vue", include_unpublished: true)
      end

      @podcast_scott_and_mark = VCR.use_cassette("contentful/readme-podcast-taking-das-blog-into-future") do
        Site::Contentful::Readme::Podcast.find("taking-das-blog-into-future", include_unpublished: true)
      end
    end

    test "#name" do
      assert_equal "Evan You", @podcast_evan.name
      assert_equal "Scott Hanselman and Mark Downie", @podcast_scott_and_mark.name
    end

    test "#github_handle" do
      assert_equal "yyx990803", @podcast_evan.github_handle
      assert_equal "poppastring/dasblog-core", @podcast_scott_and_mark.github_handle
    end

    context ".label" do
      test "returns the right label when podcast does not have a season" do
        assert_equal @podcast_evan.label, "THE README PODCAST // EPISODE 2"
      end

      test "returns the right label when podcast does have a season" do
        @podcast_evan.stubs(:season_number).returns(1)

        assert_equal @podcast_evan.label, "THE README PODCAST // S1.2"
      end
    end
  end
end
