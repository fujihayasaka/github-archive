# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module CommentPosition
    module Legacy
      class PositioningTest < GitHub::TestCase
        test "is invalid when thread is outdated" do
          positioning = Transformer.new(
            side: :left,
            start_side: nil,
            subject_type: :file,
            base_sha: "deadbeef",
            base_path: nil,
            head_sha: "feebdaed",
            head_path: "README.md",
            start_line_number: nil,
            end_line_number: nil,
            outdated: true,
          ).to_positioning

          fail unless positioning.is_a?(Positions::Invalid)
          assert_equal :outdated, positioning.reason
        end

        test "is invalid when the base_path cannot be found" do
          positioning = Transformer.new(
            side: :left,
            start_side: nil,
            subject_type: :file,
            base_sha: "deadbeef",
            base_path: nil,
            head_sha: "feebdaed",
            head_path: "README.md",
            start_line_number: nil,
            end_line_number: nil,
            outdated: false,
          ).to_positioning

          fail unless positioning.is_a?(Positions::Invalid)
          assert_equal :positioning_requires_left_path, positioning.reason
        end

        test "is invalid when the head_path cannot be found" do
          positioning = Transformer.new(
            side: :right,
            start_side: nil,
            subject_type: :file,
            base_sha: "deadbeef",
            base_path: "README.md",
            head_sha: "feebdaed",
            head_path: nil,
            start_line_number: nil,
            end_line_number: nil,
            outdated: false,
          ).to_positioning

          fail unless positioning.is_a?(Positions::Invalid)
          assert_equal :positioning_requires_right_path, positioning.reason
        end

        test "transforms valid left side file comment" do
          base_sha = "deadbeef"
          base_path = "README.md"
          head_sha = "deadbeef"
          head_path = "READMEEE.md"

          positioning = Transformer.new(
            side: :left,
            start_side: nil,
            subject_type: :file,
            base_sha:,
            base_path:,
            head_sha:,
            head_path:,
            start_line_number: nil,
            end_line_number: nil,
            outdated: false,
          ).to_positioning

          fail unless positioning.is_a?(Positions::File)
          assert_equal base_path, positioning.path
          assert_equal base_sha, positioning.commit_oid
        end

        test "transforms valid right side file comment" do
          base_sha = "deadbeef"
          base_path = "README.md"
          head_sha = "deadbeef"
          head_path = "READMEEE.md"

          positioning = Transformer.new(
            side: :right,
            start_side: nil,
            subject_type: :file,
            base_sha:,
            base_path:,
            head_sha:,
            head_path:,
            start_line_number: nil,
            end_line_number: nil,
            outdated: false,
          ).to_positioning

          fail unless positioning.is_a?(Positions::File)
          assert_equal head_path, positioning.path
          assert_equal head_sha, positioning.commit_oid
        end

        test "is invalid when the end_line_number cannot be found for line comment" do
          positioning = Transformer.new(
            side: :left,
            start_side: nil,
            subject_type: :line,
            base_sha: "deadbeef",
            base_path: "README.md",
            head_sha: "feebdaed",
            head_path: "README.md",
            start_line_number: nil,
            end_line_number: nil,
            outdated: false,
          ).to_positioning

          fail unless positioning.is_a?(Positions::Invalid)
          assert_equal :line_requires_end_line_number, positioning.reason
        end

        test "transforms valid left side line comment" do
          base_sha = "deadbeef"
          base_path = "README.md"
          head_sha = "deadbeef"
          head_path = "READMEEE.md"
          end_line_number = 10

          positioning = Transformer.new(
            side: :left,
            start_side: nil,
            subject_type: :line,
            base_sha:,
            base_path:,
            head_sha:,
            head_path:,
            start_line_number: nil,
            end_line_number:,
            outdated: false,
          ).to_positioning

          fail unless positioning.is_a?(Positions::Line)
          assert_equal end_line_number, positioning.line
          assert_equal base_path, positioning.path
          assert_equal base_sha, positioning.commit_oid
        end

        test "transforms valid right side line comment" do
          base_sha = "deadbeef"
          base_path = "README.md"
          head_sha = "deadbeef"
          head_path = "READMEEE.md"
          end_line_number = 10

          positioning = Transformer.new(
            side: :right,
            start_side: nil,
            subject_type: :line,
            base_sha:,
            base_path:,
            head_sha:,
            head_path:,
            start_line_number: nil,
            end_line_number:,
            outdated: false,
          ).to_positioning

          fail unless positioning.is_a?(Positions::Line)
          assert_equal end_line_number, positioning.line
          assert_equal head_path, positioning.path
          assert_equal head_sha, positioning.commit_oid
        end

        test "is invalid when the start_line_number cannot be found for multiline comment" do
          positioning = Transformer.new(
            side: :left,
            start_side: :left,
            subject_type: :line,
            base_sha: "deadbeef",
            base_path: "README.md",
            head_sha: "feebdaed",
            head_path: "README.md",
            start_line_number: nil,
            end_line_number: 10,
            outdated: false,
          ).to_positioning

          fail unless positioning.is_a?(Positions::Invalid)
          assert_equal :multiline_requires_start_line_number, positioning.reason
        end

        test "transforms valid left side/left start side multiline comment" do
          base_sha = "deadbeef"
          base_path = "README.md"
          head_sha = "deadbeef"
          head_path = "READMEEE.md"
          start_line_number = 5
          end_line_number = 10

          positioning = Transformer.new(
            side: :left,
            start_side: :left,
            subject_type: :line,
            base_sha:,
            base_path:,
            head_sha:,
            head_path:,
            start_line_number:,
            end_line_number:,
            outdated: false,
          ).to_positioning

          fail unless positioning.is_a?(Positions::Multiline)
          assert_equal base_path, positioning.start_path
          assert_equal start_line_number, positioning.start_line
          assert_equal base_sha, positioning.start_commit_oid
          assert_equal base_path, positioning.end_path
          assert_equal end_line_number, positioning.end_line
          assert_equal base_sha, positioning.end_commit_oid
        end

        test "transforms valid right side/right start side multiline comment" do
          base_sha = "deadbeef"
          base_path = "README.md"
          head_sha = "deadbeef"
          head_path = "READMEEE.md"
          start_line_number = 5
          end_line_number = 10

          positioning = Transformer.new(
            side: :right,
            start_side: :right,
            subject_type: :line,
            base_sha:,
            base_path:,
            head_sha:,
            head_path:,
            start_line_number:,
            end_line_number:,
            outdated: false,
          ).to_positioning

          fail unless positioning.is_a?(Positions::Multiline)
          assert_equal head_path, positioning.start_path
          assert_equal start_line_number, positioning.start_line
          assert_equal head_sha, positioning.start_commit_oid
          assert_equal head_path, positioning.end_path
          assert_equal end_line_number, positioning.end_line
          assert_equal head_sha, positioning.end_commit_oid
        end
      end
    end
  end
end
