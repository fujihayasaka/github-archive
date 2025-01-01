# typed: strict
# frozen_string_literal: true

require "test_helper"

class TopicChangesetTest < GitHub::TestCase
  context "#changed?" do
    test "false when the only difference is a duplicate alias" do
      topic = create :topic
      topic.update_aliases_from_names("duck, goose")
      changeset = TopicChangeset.new(topic)
      changeset.determine_changes("aliases" => "duck, duck, goose")
      refute_predicate changeset, :changed?
    end

    test "false when the only difference is a duplicate related topic" do
      topic = create :topic
      topic.update_related_topics_from_names("duck, goose")
      changeset = TopicChangeset.new(topic)
      changeset.determine_changes("related" => "duck, duck, goose")
      refute_predicate changeset, :changed?
    end
  end
end
