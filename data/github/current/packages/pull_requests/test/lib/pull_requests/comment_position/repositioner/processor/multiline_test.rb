# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "mock_command"
require_relative "test_case"

module PullRequests
  module CommentPosition
    module Repositioner
      class MultilineTest < TestCase
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
            [1, 3],
            [1, 3],
            [1, 3],
            [3, 5],
            [4, 6],
          ])

          # Range to query the entire range of commits.
          @commit_range = Positions::DiffRange.new(
            base_commit_oid: @commit_graph.first,
            start_commit_oid: @commit_graph.first,
            end_commit_oid: @commit_graph.last,
          )
        end

        test "positions are recomputed when position data does not match the requested range" do
          start_commit_oid = @commit_graph.first
          start_line = 1
          start_path = "README.md"

          end_commit_oid = @commit_graph.last
          end_line = 3
          end_path = "EMDAER.md"

          original_positioning = Positions::Multiline.new(
            range: @commit_range,
            start_line:,
            start_path:,
            start_commit_oid:,
            end_line:,
            end_path:,
            end_commit_oid:,
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
          start_line = 1
          start_path = "README.md"
          end_line = 3
          end_path = start_path
          commit_oid = @commit_graph.first

          original_positioning = Positions::Multiline.new(
            range: @commit_range,
            start_line:,
            start_path:,
            start_commit_oid: commit_oid,
            end_line:,
            end_path:,
            end_commit_oid: commit_oid,
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
          raise "expected Multiline position, got #{positioning.class.inspect}" unless positioning.is_a?(Positions::Multiline)

          assert_equal start_line, positioning.start_line
          assert_equal start_path, positioning.start_path
          assert_equal commit_oid, positioning.start_commit_oid
          assert_equal end_line, positioning.end_line
          assert_equal end_path, positioning.end_path
          assert_equal commit_oid, positioning.end_commit_oid
          assert_equal range, positioning.range
        end
      end
    end
  end
end
