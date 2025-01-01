# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumn::Interface::Indexable::Processor::ProcessedResultTest < GitHub::TestCase
  context "validations" do
    test "throws when failure reason is not a valid value" do
      assert_raises ArgumentError do
        klass.new(failure_reason: "eh?")
      end
    end

    test "throws when neither failure_reason and elasticsearch_update_response are provided" do
      assert_raises ArgumentError do
        klass.new(
          failure_reason: nil,
          elasticsearch_update_response: nil,
        )
      end
    end

    test "throws when both failure_reason and elasticsearch_update_response are provided" do
      assert_raises ArgumentError do
        klass.new(
          failure_reason: MemexProjectColumn::Interface::Indexable::Processor::FailureReason::NO_MATCHING_DOCS,
          elasticsearch_update_response: update_response({ foo: :bar }),
        )
      end
    end
  end

  PREDICATES = {
    no_matching_docs?: MemexProjectColumn::Interface::Indexable::Processor::FailureReason::NO_MATCHING_DOCS,
    content_missing?:  MemexProjectColumn::Interface::Indexable::Processor::FailureReason::CONTENT_MISSING,
    message_ignored?:  MemexProjectColumn::Interface::Indexable::Processor::FailureReason::MESSAGE_IGNORED,
    project_missing?:  MemexProjectColumn::Interface::Indexable::Processor::FailureReason::PROJECT_MISSING,
    partial_resync?:   MemexProjectColumn::Interface::Indexable::Processor::FailureReason::PARTIAL_RESYNC,
  }
  PREDICATES.each do |method_name, failure_reason|
    context "##{method_name}" do
      test "true when the failure reason matches #{failure_reason}" do
        instance = klass.new(failure_reason: failure_reason)
        assert_predicate instance, method_name
      end

      test "false when the failure reason does not match #{failure_reason}" do
        other = PREDICATES.values.reject { |k| k == failure_reason }.first
        instance = klass.new(failure_reason: other)
        refute_predicate instance, method_name
      end
    end
  end

  context "#failure_reason?" do
    test "true whe the outcome has a failure_reason key" do
      reason = MemexProjectColumn::Interface::Indexable::Processor::FailureReason::PROJECT_MISSING
      instance = klass.new(failure_reason: reason)
      assert_predicate instance, :failure_reason?
    end

    test "false whe the outcome does not have a failure_reason key" do
      instance = klass.new(elasticsearch_update_response: update_response({ "version_conflicts" => 1 }))
      refute_predicate instance, :failure_reason?
    end
  end

  context "#conflict_count" do
    test "returns the value of the version_conflicts key when present" do
      conflict_count = 1
      instance = klass.new(elasticsearch_update_response: update_response({ "version_conflicts" => conflict_count }))
      assert_equal conflict_count, instance.conflict_count
    end

    test "returns 0 when the version_conflicts key is not present" do
      conflict_count = 0
      instance = klass.new(elasticsearch_update_response: update_response({}))
      assert_equal conflict_count, instance.conflict_count
    end
  end

  context "#version_conflicts?" do
    test "true when the outcome has a version_conflicts key with a value greater than 0" do
      instance = klass.new(elasticsearch_update_response: update_response({ "version_conflicts" => 1 }))
      assert_predicate instance, :version_conflicts?
    end

    test "false when the outcome has no version_conflicts key" do
      instance = klass.new(elasticsearch_update_response: update_response({ "foo" => :bar }))
      refute_predicate instance, :version_conflicts?
    end

    test "false when the outcome has a version_conflicts key with a value equal to 0" do
      instance = klass.new(elasticsearch_update_response: update_response({ "version_conflicts" => 0 }))
      refute_predicate instance, :version_conflicts?
    end
  end

  context "#failures_or_errors_to_report?" do
    test "true when the outcome has a non-empty failures key" do
      instance = klass.new(elasticsearch_update_response: update_response({ "failures" => ["?"] }))
      assert_predicate instance, :failures_or_errors_to_report?
    end

    test "true when the outcome has a non-empty errors key" do
      instance = klass.new(elasticsearch_update_response: update_response({ "errors" => ["?"] }))
      assert_predicate instance, :failures_or_errors_to_report?
    end

    test "false when the outcome has neither a failures nor an errors key" do
      instance = klass.new(elasticsearch_update_response: update_response({ "foo" => :bar }))
      refute_predicate instance, :failures_or_errors_to_report?
    end
  end

  private def klass
    MemexProjectColumn::Interface::Indexable::Processor::ProcessedResult
  end

  private def update_response(data)
    MemexProjectColumn::Interface::Indexable::Processor::ElasticsearchUpdateResponse.new(data:)
  end
end
