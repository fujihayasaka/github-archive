# frozen_string_literal: true

require "test_helper"

module AdvisoryDBToolkit
  class UtilityTest < Minitest::Test
    class RespondsToEmpty
      def initialize(empty)
        @empty = empty
      end

      def empty?
        @empty
      end
    end

    class DoesNotRespondToEmpty; end # rubocop:disable Lint/EmptyClass

    def setup
      @subject = AdvisoryDBToolkit::Utility
    end

    def test_blank_true_if_nil_falsey_or_empty
      assert @subject.blank?(nil)
      assert @subject.blank?(false)
      assert @subject.blank?("")

      empty_true = RespondsToEmpty.new(true)
      empty_false = RespondsToEmpty.new(false)
      not_empty = DoesNotRespondToEmpty.new
      assert @subject.blank?(empty_true)
      refute @subject.blank?(empty_false)
      refute @subject.blank?(not_empty)
    end
  end
end
