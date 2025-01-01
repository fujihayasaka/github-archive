# typed: true
# frozen_string_literal: true

require "test_helper"

class Site::Contentful::Readme::Pages::Topics::ShowPageTest < GitHub::TestCase
  require_cassettes_for_external_http_connections

  unless GitHub.enterprise?
    setup do
      @culture_topic = VCR.use_cassette("contentful/readme-topic-culture") do
        Site::Contentful::Readme::Topic.find("culture")
      end

      @culture_stories = VCR.use_cassette("contentful/readme-topic-culture-all-stories") do
        Timecop.freeze(Time.utc(2022, 5, 2)) { Site::Contentful::Readme::Topic.find_stories_for(@culture_topic.id) }
      end

      @show_page_for_non_staff = Site::Contentful::Readme::Pages::Topics::ShowPage.new(topic_slug: @culture_topic.slug)

      @show_page_for_non_staff_with_fake_topic = Site::Contentful::Readme::Pages::Topics::ShowPage.new(topic_slug: "not-a-real-topic")

      @show_page_for_staff = Site::Contentful::Readme::Pages::Topics::ShowPage.new(topic_slug: @culture_topic.slug, for_readme_staff: true)
    end

    context "#fetch_data_from_contentful" do
      test "returns a blank result if the topic is not found" do
        VCR.use_cassette("contentful/readme-topics-show-page-not-found") do
          result = @show_page_for_non_staff_with_fake_topic.fetch_data_from_contentful

          assert_nil result[:topic]
          assert_empty result[:stories]
          assert_empty result[:navigation_topics]
        end
      end

      test "returns data from Contentful if the topic is found" do
        VCR.use_cassette("contentful/readme-topics-show-page") do
          # We need to freeze time because Topic.find_stories_for use the current time to get
          # the list of published stories.
          Timecop.freeze(Time.utc(2022, 5, 2)) do
            result = @show_page_for_non_staff.fetch_data_from_contentful

            assert_equal @culture_topic.to_json, result[:topic]

            assert_equal 4, result[:navigation_topics].count
            assert_equal "Open Source", result[:navigation_topics][0][:name]
            assert_equal "Culture", result[:navigation_topics][1][:name]
            assert_equal "Security", result[:navigation_topics][2][:name]
            assert_equal "DevOps", result[:navigation_topics][3][:name]
          end
        end
      end

      context "handling stories cache key" do
        test "returns the right cache key for non-staff" do
          VCR.use_cassette("contentful/readme-topics-show-page") do
            Timecop.freeze(Time.utc(2022, 5, 2)) do
              result = @show_page_for_non_staff.fetch_data_from_contentful

              assert result[:stories_cache_key].end_with?("for_readme_staff:false/v1")
            end
          end
        end

        test "returns the right cache key for staff" do
          VCR.use_cassette("contentful/readme-topics-show-page-for-staff") do
            Timecop.freeze(Time.utc(2022, 5, 2)) do
              result = @show_page_for_staff.fetch_data_from_contentful

              assert result[:stories_cache_key].end_with?("for_readme_staff:true/v1")
            end
          end
        end

        test "builds the right cache_key" do
          VCR.use_cassette("contentful/readme-topics-show-page") do
            Timecop.freeze(Time.utc(2022, 5, 2)) do
              result = @show_page_for_non_staff.fetch_data_from_contentful

              assert_match /[a-f0-9]{64}.for_readme_staff:false\/v1/, result[:stories_cache_key]
            end
          end
        end
      end
    end

    context "#cache_key" do
      test "builds the right cache key" do
        assert_equal "site.swp.readme.topics.culture.staff:false", @show_page_for_non_staff.cache_key
        assert_equal "site.swp.readme.topics.culture.staff:true", @show_page_for_staff.cache_key
      end
    end
  end
end
