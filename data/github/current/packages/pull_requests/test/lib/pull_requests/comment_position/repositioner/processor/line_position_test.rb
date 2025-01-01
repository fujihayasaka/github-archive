# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "mock_command"
require_relative "test_case"

module PullRequests
  module CommentPosition
    module Repositioner
      class LinePositionTest < TestCase
        setup do
          # Build a fake "commit range"
          @commit_graph = [
            oid_sequence.next, # A
            oid_sequence.next, # B
            oid_sequence.next, # C
            oid_sequence.next, # D
            oid_sequence.next, # E
          ]

          # Map file names at specific verisons in the commit range.
          @file_names = @commit_graph.zip([
            "README.md",
            "README.md",
            "README.md",
            "README.md",
            "EMDAER.md"
          ]).to_h

          @line_numbers = @commit_graph.zip([
            1,
            1,
            1,
            3,
            4,
          ])

          # Range to query the entire range of commits.
          @commit_range = Positions::DiffRange.new(
            base_commit_oid: @commit_graph.first,
            start_commit_oid: @commit_graph.first,
            end_commit_oid: @commit_graph.last,
          )
        end

        test "positions are recomputed when position data does not match the requested range" do
          line = 1
          path = "README.md"
          commit_oid = @commit_graph.last

          original_positioning = Positions::Line.new(
            range: @commit_range,
            line:,
            path:,
            commit_oid:
          )

          request = Request.new(
            identifier: 1,
            original_positioning:,
          )

          range = Positions::DiffRange.new(
            base_commit_oid: @commit_graph.first,
            start_commit_oid: @commit_graph.first,
            end_commit_oid: @commit_graph.second,
          )

          result = Processor.new(
            command: Logging::Commands.new(delegate: MockCommand.new),
            requests: [request],
            range:
          ).call

          # TODO: This will get repositioned once the functionality exists, so this test will end up a "happy path" test.
          assert_nil result[request]
        end

        test "positions can be reused if they target a specific side of the diff" do
          line = 1
          path = "README.md"
          commit_oid = @commit_graph.first

          original_positioning = Positions::Line.new(
            range: @commit_range,
            line:,
            path:,
            commit_oid:
          )

          request = Request.new(
            identifier: 1,
            original_positioning:,
          )

          range = Positions::DiffRange.new(
            base_commit_oid: @commit_graph.first,
            start_commit_oid: @commit_graph.first,
            end_commit_oid: @commit_graph.second,
          )

          result = Processor.new(
            command: Logging::Commands.new(delegate: MockCommand.new),
            requests: [request],
            range:
          ).call

          positioning = result[request]
          raise "expected line position, got #{positioning.class.inspect}" unless positioning.is_a?(Positions::Line)

          assert_equal line, positioning.line
          assert_equal path, positioning.path
          assert_equal commit_oid, positioning.commit_oid
          assert_equal range, positioning.range
        end
      end
    end
  end
end
