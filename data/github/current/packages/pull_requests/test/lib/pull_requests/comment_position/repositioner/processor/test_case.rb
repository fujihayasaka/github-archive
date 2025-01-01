# typed: strict
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module CommentPosition
    module Repositioner
      # Shared base test class for various line type tests.
      class TestCase < GitHub::TestCase
        include GitHub::Memoizer

        private

        sig { params(a: Positions, b: Positions).returns(T::Boolean) }
        def assert_positions_equal(a, b)
          assert_equal a.serialize, b.serialize
        end

        sig { returns(Positions::DiffRange) }
        def build_diff_range
          base_commit_oid = oid_sequence.next
          start_commit_oid = oid_sequence.next
          end_commit_oid = oid_sequence.next

          Positions::DiffRange.new(base_commit_oid:, start_commit_oid:, end_commit_oid:)
        end

        # Helper to make fake looking SHAs predictably.
        sig { returns(T::Enumerator[String]) }
        memoize def oid_sequence
          Enumerator.new do |y|
            value = 0
            loop do
              y << value.to_s(16).rjust(40, "0")
              value += 1
            end
          end
        end
      end
    end
  end
end
