# typed: true
# frozen_string_literal: true

require "test_helper"

class Site::Contentful::Readme::DeveloperStoryTest < GitHub::TestCase
  require_cassettes_for_external_http_connections

  unless GitHub.enterprise?
    setup do
      @developer_story_brian = VCR.use_cassette("contentful/readme-developer-story-brian-douglas") do
        Site::Contentful::Readme::DeveloperStory.find("brian-douglas", include_unpublished: true)
      end

      @developer_story_henry = VCR.use_cassette("contentful/readme-developer-story-henry-zhu") do
        Site::Contentful::Readme::DeveloperStory.find("henry-zhu", include_unpublished: true)
      end
    end

    test "#name" do
      assert_equal "Brian Douglas", @developer_story_brian.name
      assert_equal "Henry Zhu", @developer_story_henry.name
    end

    test "#project_name" do
      assert_equal "open-sauced", @developer_story_brian.project_name
      assert_equal "Babel", @developer_story_henry.project_name
    end

    test "#label" do
      assert_equal "Brian Douglas // open-sauced", @developer_story_brian.label
      assert_equal "Henry Zhu // Babel", @developer_story_henry.label
    end

    test "#meta_title" do
      @developer_story_brian.seo.stubs(:meta_title).returns("Custom title")
      @developer_story_henry.seo.stubs(:meta_title).returns(nil)

      assert_equal "Custom title", @developer_story_brian.meta_title
      assert_equal @developer_story_henry.name, @developer_story_henry.meta_title
    end

    test "#open_graph_title" do
      @developer_story_brian.seo.stubs(:open_graph_title).returns("Custom og:title")
      @developer_story_henry.seo.stubs(:open_graph_title).returns(nil)

      assert_equal "Custom og:title", @developer_story_brian.open_graph_title
      assert_equal @developer_story_henry.name, @developer_story_henry.open_graph_title
    end

    context "older content model without SEO on stories" do
      test "#meta_title" do
        @developer_story_no_seo = VCR.use_cassette("contentful/readme-developer-story-no-seo-content-model") do
          Site::Contentful::Readme::DeveloperStory.find("brian-douglas", include_unpublished: true)
        end

        assert_equal @developer_story_no_seo.name, @developer_story_no_seo.meta_title
      end

      test "#open_graph_title" do
        @developer_story_no_seo = VCR.use_cassette("contentful/readme-developer-story-no-seo-content-model") do
          Site::Contentful::Readme::DeveloperStory.find("brian-douglas", include_unpublished: true)
        end

        assert_equal @developer_story_no_seo.name, @developer_story_no_seo.open_graph_title
      end
    end
  end
end
