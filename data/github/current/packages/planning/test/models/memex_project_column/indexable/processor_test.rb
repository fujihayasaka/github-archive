# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumnIndexableProcessorTest < GitHub::TestCase
  include HydroTestHelpers

  test "registers only subclasses of MemexProjectColumn::Interface::Indexable::Processor::Base" do
    MemexProjectColumn::Interface::Indexable::Processor::registered_processors.each do |processor|
      begin
        assert(
          processor < MemexProjectColumn::Interface::Indexable::Processor::Base,
          "#{processor} is not a subclass of MemexProjectColumn::Interface::Indexable::Processor::Base."
        )
      rescue NameError
        assert_nil(
          class_name,
          "#{class_name} does not exist. " +
          "Please correct or remove it"
        )
      end
    end
  end

  test "returns array of topics for non-field processors" do
    known_registered_processor = MemexProjectColumn::Interface::Indexable::Processor::ContentStateChange
    known_registered_topics = known_registered_processor.topics
    registered_topics = MemexProjectColumn::Interface::Indexable::Processor.registered_topics
    known_registered_topics.each do |topic|
      assert_includes registered_topics, topic
    end
  end

  test "returns array of topics for field-registered processors" do
    known_registered_topic = /github\.v1\.IssueUpdateAssignee\Z/
    registered_topics = MemexProjectColumn::Interface::Indexable::Processor.registered_topics
    assert_includes registered_topics, known_registered_topic
  end

  test "omits any fields that have been excluded from indexing" do
    # This first section just validates that our fixtures have the expected data
    known_registering_field = MemexProjectColumn::Field::Assignees
    known_registered_processor = "MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateAssignee"
    known_registered_topic = /github\.v1\.IssueUpdateAssignee\Z/
    assert_includes known_registering_field.register_processors, known_registered_processor
    assert_includes known_registered_processor.constantize.topics, known_registered_topic
    assert_includes MemexProjectColumn::Interface::Indexable::Processor.registered_topics, known_registered_topic

    known_registering_field.expects(:exclude_from_index?).returns(true)
    refute_includes MemexProjectColumn::Interface::Indexable::Processor.registered_topics, known_registered_topic
  end

  test "returns matching registered processor for a given message" do
    known_registered_processor = MemexProjectColumn::Interface::Indexable::Processor::ContentStateChange
    schema = "github.v1.PullRequestMerge"
    message = build_message({}, schema: schema)
    processors = MemexProjectColumn::Interface::Indexable::Processor.for_message(message)
    assert_equal processors.size, 1
    assert processors.first.is_a? known_registered_processor
  end
end
