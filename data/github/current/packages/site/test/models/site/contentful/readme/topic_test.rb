# typed: true
# frozen_string_literal: true

require "test_helper"

class Site::Contentful::Readme::TopicTest < GitHub::TestCase
  require_cassettes_for_external_http_connections

  unless GitHub.enterprise?
    setup do
      @topic = VCR.use_cassette("contentful/readme-topic-culture") do
        Site::Contentful::Readme::Topic.find("culture")
      end
    end

    context ".find_stories_for" do
      test "returns all the latest stories for the topic" do
        VCR.use_cassette("contentful/readme-topic-culture-all-stories") do
          Timecop.freeze(Time.utc(2022, 5, 2)) do
            stories = Site::Contentful::Readme::Topic.find_stories_for(@topic.id)

            assert_equal "Featured Article", stories.first.name
            assert_equal "featured", stories.first.content_type.id
            assert_equal DateTime.parse("2022-04-12T02:00:00+00:00"), stories.first.publication_date

            assert_equal "Monica Powell", stories.second.name
            assert_equal "guide", stories.second.content_type.id
            assert_equal DateTime.parse("2022-02-08T02:00:00+00:00"), stories.second.publication_date

            assert_equal "John Allspaw", stories.third.name
            assert_equal "guide", stories.third.content_type.id
            assert_equal DateTime.parse("2022-02-08T02:00:00+00:00"), stories.third.publication_date

            assert_equal "Featured Article", stories.fourth.name
            assert_equal "featured", stories.fourth.content_type.id
            assert_equal DateTime.parse("2022-02-08T02:00:00+00:00"), stories.fourth.publication_date

            assert_equal "Monica Powell", stories.fifth.name
            assert_equal "guide", stories.fifth.content_type.id
            assert_equal DateTime.parse("2022-01-12T02:00:00+00:00"), stories.fifth.publication_date

            assert_equal 66, stories.count
          end
        end
      end

      test "returns the latest four stories for the topic" do
        VCR.use_cassette("contentful/readme-topic-culture-four-stories") do
          Timecop.freeze(Time.utc(2022, 5, 2)) do
            stories = Site::Contentful::Readme::Topic.find_stories_for(@topic.id, take: 4)

            assert_equal "Featured Article", stories.first.name
            assert_equal "featured", stories.first.content_type.id
            assert_equal DateTime.parse("2022-04-12T02:00:00+00:00"), stories.first.publication_date

            assert_equal "Monica Powell", stories.second.name
            assert_equal "guide", stories.second.content_type.id
            assert_equal DateTime.parse("2022-02-08T02:00:00+00:00"), stories.second.publication_date

            assert_equal "John Allspaw", stories.third.name
            assert_equal "guide", stories.third.content_type.id
            assert_equal DateTime.parse("2022-02-08T02:00:00+00:00"), stories.third.publication_date

            assert_equal "Featured Article", stories.fourth.name
            assert_equal "featured", stories.fourth.content_type.id
            assert_equal DateTime.parse("2022-02-08T02:00:00+00:00"), stories.fourth.publication_date

            assert_equal 4, stories.count
          end
        end
      end
    end

    context "#to_json" do
      test "returns the topic as a JSON-like hash" do
        json = @topic.to_json

        assert_equal "Culture", json[:name]
        assert_equal "culture", json[:slug]
        assert_equal "4tOMNQrRetc24Ezm9c5DtD", json[:id]
        assert_equal "The softer side of software development.", json[:meta_text]
      end
    end
  end
end
