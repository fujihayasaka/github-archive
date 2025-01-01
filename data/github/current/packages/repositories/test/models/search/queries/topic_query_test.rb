# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchQueriesTopicQueryTest < GitHub::TestCase
  fixtures do
    @user = create(:user)

    @public_repo = create(:repository, owner: @user)
    @private_repo = create(:private_repository, owner: @user)

    @public_topic = create(:topic, name: "public-topic")
    @private_topic = create(:topic, name: "private-topic")
    @shared_topic = create(:topic, name: "shared-topic")

    create(:repository_topic, repository: @public_repo, topic: @public_topic)
    create(:repository_topic, repository: @private_repo, topic: @private_topic)
    create(:repository_topic, repository: @public_repo, topic: @shared_topic)
    create(:repository_topic, repository: @private_repo, topic: @shared_topic)
  end

  setup do
    setup_search

    make_searchable @public_topic, @private_topic, @shared_topic
  end

  teardown do
    teardown_search
  end

  test "returns only topics applied to at least one public repository" do
    query = Search::Queries::TopicQuery.new(current_user: @user, query: "topic")
    results = query.execute

    assert_same_elements [@public_topic, @shared_topic], results.models

    public_result = results.find { |r| r["_model"] == @public_topic }
    assert_equal 1, public_result["_source"]["repository_count"]
    shared_result = results.find { |r| r["_model"] == @shared_topic }
    assert_equal 1, shared_result["_source"]["repository_count"]
  end

  context "valid query" do
    test "empty phrase query returns not valid query" do
      query = Search::Queries::TopicQuery.new(current_user: @user, phrase: " ")
      refute_predicate query, :valid_query?
    end

    test "phrase query returns valid query" do
      query = Search::Queries::TopicQuery.new(current_user: @user, phrase: "test")
      assert_predicate query, :valid_query?
    end
  end
end
