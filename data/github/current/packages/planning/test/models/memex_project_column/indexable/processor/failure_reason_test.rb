# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumn::Indexable::Processor::FailureReasonTest < GitHub::TestCase
  context "::invalid?" do
    test "returns true when the failure reason is not in the combined set" do
      assert klass.invalid?("not-in-the-set")
    end

    test "returns false when the failure reason is nil" do
      refute klass.invalid?(nil)
    end

    test "returns false when the failure reason is an empty string" do
      refute klass.invalid?(nil)
    end

    MemexProjectColumn::Indexable::Processor::FailureReason::COMBINED_SET.each do |reason|
      test "returns false when the failure reason is in the combined set: #{reason}" do
        refute klass.invalid?(reason)
      end
    end
  end

  private def klass
    MemexProjectColumn::Indexable::Processor::FailureReason
  end
end
