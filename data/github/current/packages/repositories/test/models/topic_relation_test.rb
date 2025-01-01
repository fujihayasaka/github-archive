# typed: strict
# frozen_string_literal: true

require "test_helper"

class TopicRelationTest < GitHub::TestCase
  test "reindexes aliased topic on save" do
    source_topic = create(:topic, name: "parent-topic")
    topic = create(:topic, name: "child-topic")

    reset_job_hash_locks

    assert_enqueued_with job: RemoveFromSearchIndexJob, args: ["topic", topic.id] do
      create(:topic_relation, topic: source_topic, relation_type: :alias, name: topic.name)
    end
  end

  test "does not reindex related topic on save" do
    source_topic = create(:topic, name: "parent-topic")
    topic = create(:topic, name: "related-topic")

    assert_enqueued_jobs 0, only: RemoveFromSearchIndexJob do
      create(:topic_relation, topic: source_topic, relation_type: :related, name: topic.name)
    end
  end

  context "with_relation_type scope" do
    test "returns relations with the given type name" do
      relation1 = create(:topic_relation, relation_type: :related)
      relation2 = create(:topic_relation, relation_type: :alias)

      results = TopicRelation.with_relation_type(:related)

      assert_includes results, relation1
      refute_includes results, relation2
    end

    test "returns relations with the given type value" do
      relation1 = create(:topic_relation, relation_type: :related)
      relation2 = create(:topic_relation, relation_type: :alias)

      results = TopicRelation.with_relation_type(TopicRelation.relation_types[:alias])

      refute_includes results, relation1
      assert_includes results, relation2
    end
  end

  context "without_relation_type scope" do
    test "returns relations without the given type name" do
      relation1 = create(:topic_relation, relation_type: :related)
      relation2 = create(:topic_relation, relation_type: :alias)

      results = TopicRelation.without_relation_type(:related)

      refute_includes results, relation1
      assert_includes results, relation2
    end

    test "returns relations without the given type value" do
      relation1 = create(:topic_relation, relation_type: :related)
      relation2 = create(:topic_relation, relation_type: :alias)

      results = TopicRelation.without_relation_type(TopicRelation.relation_types[:alias])

      assert_includes results, relation1
      refute_includes results, relation2
    end
  end

  test "requires name" do
    topic_relation = TopicRelation.new(name: nil)
    refute_predicate topic_relation, :valid?
    assert topic_relation.errors[:name]
  end

  test "validates length of name" do
    topic_relation = TopicRelation.new(name: "a" * 36)
    refute_predicate topic_relation, :valid?
    assert topic_relation.errors[:name]
  end

  test "rejects name containing emojis" do
    topic_relation = TopicRelation.new(name: "🐹")
    refute_predicate topic_relation, :valid?
    assert topic_relation.errors[:name]
  end

  test "requires topic" do
    topic_relation = TopicRelation.new(topic: nil)
    refute_predicate topic_relation, :valid?
    assert topic_relation.errors[:topic]
  end

  test "disallows more than MAX_TOPIC_ALIASES aliases for a single topic" do
    topic = create :topic
    TopicRelation::MAX_TOPIC_ALIASES.times do |i|
      create(:topic_relation, relation_type: :alias, topic: topic, name: "alias-#{i}")
    end
    topic_relation = build(:topic_relation, relation_type: :alias, topic: topic,
                                                name: "new-alias")

    refute_predicate topic_relation, :valid?
    assert_includes topic_relation.errors[:topic],
      "cannot have more than #{TopicRelation::MAX_TOPIC_ALIASES} aliases"
  end

  test "disallows more than MAX_RELATED_TOPICS related topics for a single topic" do
    topic = create :topic
    TopicRelation::MAX_RELATED_TOPICS.times do |i|
      create(:topic_relation, relation_type: :related, topic: topic, name: "related-topic-#{i}")
    end
    topic_relation = build(:topic_relation, relation_type: :related, topic: topic,
                                                name: "new-related-topic")

    refute_predicate topic_relation, :valid?
    assert_includes topic_relation.errors[:topic],
      "cannot have more than #{TopicRelation::MAX_RELATED_TOPICS} related topics"
  end

  test "does not allow the same alias for multiple topics" do
    topic1 = create :topic
    topic2 = create :topic
    alias_name = "fidget-spinner"

    create(:topic_relation, topic: topic1, name: alias_name, relation_type: :alias)
    relation = build(:topic_relation, topic: topic2, name: alias_name, relation_type: :alias)

    refute_predicate relation, :valid?
    assert relation.errors[:name]
  end

  context "#alias?" do
    test "true when relation_type is alias" do
      assert_predicate create(:topic_relation, relation_type: :alias), :alias?
    end

    test "false when relation_type is related" do
      refute_predicate create(:topic_relation, relation_type: :related), :alias?
    end
  end
end
