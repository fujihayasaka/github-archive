# typed: true
# frozen_string_literal: true

require "test_helper"
require "munger/client"

class RepositoryTopicsDependencyTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @repo = create(:repository)
  end

  context "#topic_names" do
    test "returns names of applied topics on the repository, sorted alphabetically" do
      topic1 = create(:topic, name: "mug")
      topic2 = create(:topic, name: "glass")
      topic3 = create(:topic, name: "tumbler")

      create(:repository_topic, repository: @repo, topic: topic1)
      create(:repository_topic, repository: @repo, topic: topic2)
      create(:repository_topic, repository: @repo, topic: topic3)

      assert_equal %w[glass mug tumbler], @repo.topic_names
    end

    test "is empty for repo without topics" do
      assert_empty @repo.topic_names
    end

    test "is empty for repo without applied topics" do
      create(:repository_topic, repository: @repo, state: :declined_personal_preference)
      assert_empty @repo.topic_names
    end
  end

  context "#update_topics" do
    test "returns false when topic count exceeds limit" do
      RepositoryTopic.stub_const(:LIMIT_PER_REPOSITORY, 2) do
        topics = %w(too much fun)
        result = @repo.update_topics(topics, user: @repo.owner)

        refute result
        assert_includes @repo.errors[:repository_topics], "A repository cannot have more than #{RepositoryTopic::LIMIT_PER_REPOSITORY} topics."
        assert_equal 0, @repo.topics.count
      end
    end

    test "returns an error for invalid topic names" do
      topics = %w(too much fun -is%bad and|not+productive)
      result = @repo.update_topics(topics, user: @repo.owner)
      error_message = "must start with a lowercase letter or number, "\
        "consist of #{Topic::MAX_NAME_LENGTH} characters or less, and can include hyphens."

      refute result
      assert_includes @repo.errors[:repository_topics], error_message
      assert_equal 0, @repo.topics.count
    end

    test "repository owner can update topics" do
      assert_equal 0, @repo.topics.count

      topics = %w(fun awesome)
      result = @repo.update_topics(topics, user: @repo.owner)

      assert result
      assert_same_elements topics, @repo.topic_names
    end

    test "creates hydro event for added topic" do
      Timecop.freeze do
        updated_at = @repo.updated_at
        topics = %w(fun awesome)
        assert @repo.update_topics(topics, user: @repo.owner)
        # Match using timestamp value used in events
        @repo.updated_at = updated_at

        message1 = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          repository: Hydro::EntitySerializer.repository(@repo),
          repository_owner: Hydro::EntitySerializer.user(@repo.owner),
          action: :ACTION_TOPIC_CREATED,
          actor: Hydro::EntitySerializer.user(@repo.owner),
          topic: Hydro::EntitySerializer.topic(@repo.topics.find_by(name: "fun"))
        }

        message2 = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          repository: Hydro::EntitySerializer.repository(@repo),
          repository_owner: Hydro::EntitySerializer.user(@repo.owner),
          action: :ACTION_TOPIC_CREATED,
          actor: Hydro::EntitySerializer.user(@repo.owner),
          topic: Hydro::EntitySerializer.topic(@repo.topics.find_by(name: "awesome"))
        }

        assert_hydro_published(message1, schema: "github.v1.TopicsData")
        assert_hydro_published(message2, schema: "github.v1.TopicsData")
        assert_hydro_messages(count: 2, schema: "github.v1.TopicsData")
      end
    end
  end

  context "topics relation" do
    test "includes only the applied topics" do
      good_topic1 = create :topic
      good_topic2 = create :topic
      bad_topic1 = create :topic
      bad_topic2 = create :topic
      bad_topic3 = create :topic
      bad_topic4 = create :topic

      create(:repository_topic, repository: @repo, topic: good_topic1, state: :created)
      create(:repository_topic, repository: @repo, topic: good_topic2, state: :suggested)
      create(:repository_topic, repository: @repo, topic: bad_topic1,
                           state: :declined_not_relevant)
      create(:repository_topic, repository: @repo, topic: bad_topic2,
                           state: :declined_too_specific)
      create(:repository_topic, repository: @repo, topic: bad_topic3,
                           state: :declined_personal_preference)
      create(:repository_topic, repository: @repo, topic: bad_topic4,
                           state: :declined_too_general)

      assert_same_elements [good_topic1, good_topic2], @repo.topics
    end
  end

  context "search and indexing" do
    test "reindexes topics when repository visibilty is changed" do
      topic = create(:topic, name: "shhh")
      create(:repository_topic, repository: @repo, topic: topic)

      Topic.any_instance.expects(:synchronize_search_index).once

      assert @repo.toggle_visibility(actor: @repo.owner)
    end
  end
end
