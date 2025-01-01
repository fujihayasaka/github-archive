# typed: strict
# frozen_string_literal: true

require "test_helper"
require "munger/client"

class TopicSourceTest < GitHub::TestCase
  test "with a valid source" do
    repo = create(:repository)
    topic = create(:topic)
    source = TopicSource.create(
      source_type: "Repository",
      source_id: repo.id,
      topic: topic,
      slug: "abc123",
    )
    assert_predicate source, :valid?
  end

  test "with an invalid source" do
    topic = create(:topic)
    source = TopicSource.create(
      source_type: "Repository",
      source_id: 123987,
      topic: topic,
      slug: "abc123",
    )
    refute_predicate source, :valid?
    assert_includes source.errors.messages[:source], "can't be blank"
  end

  test "with an invalid source type" do
    topic = create(:topic)
    source = TopicSource.create(
      source_type: "Topic",
      source_id: topic.id,
      topic: topic,
      slug: "abc123",
    )
    refute_predicate source, :valid?
    assert_includes source.errors.messages[:source_type], "is not included in the list"
  end
end
