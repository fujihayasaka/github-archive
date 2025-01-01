# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumn::Interface::Indexable::Processor::ResyncProjectsResultTest < GitHub::TestCase
  context "validations" do
    test "throws when failure reason is not a valid value" do
      assert_raises ArgumentError do
        klass.new(failure_reason: "eh?")
      end
    end

    test "does not throw when neither failure_reason and elasticsearch_update_response are provided" do
      assert_nothing_raised do
        klass.new(
          failure_reason: nil,
          elasticsearch_update_response: nil,
        )
      end
    end
  end

  private def klass
    MemexProjectColumn::Interface::Indexable::Processor::ResyncProjectsResult
  end
end
