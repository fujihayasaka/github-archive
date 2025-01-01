# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module CommentPosition
    module PositionsTest
      class LineTest < GitHub::TestCase
        setup do
          range = PullRequests::CommentPosition::Positions::DiffRange.new(
            base_commit_oid: "deadbeef",
            start_commit_oid: "deadbeef",
            end_commit_oid: "feebdaed",
          )
          @position = PullRequests::CommentPosition::Positions::Line.new(
            line: 1,
            path: "README.md",
            commit_oid: "deadbeef",
            range:,
          )
        end

        context "#as_json" do
          test "only includes expected fields" do
            expected = {
              "type" => "LINE",
              "path" => "README.md",
              "line" => 1,
              "commit_oid" => "deadbeef",
            }
            assert_equal expected, @position.as_json
          end
        end
      end

      class MultilineTest < GitHub::TestCase
        setup do
          range = PullRequests::CommentPosition::Positions::DiffRange.new(
            base_commit_oid: "deadbeef",
            start_commit_oid: "deadbeef",
            end_commit_oid: "feebdaed",
          )
          @position = PullRequests::CommentPosition::Positions::Multiline.new(
            start_path: "README.md",
            start_line: 1,
            start_commit_oid: "deadbeef",
            end_path: "README.md",
            end_line: 2,
            end_commit_oid: "feebdaed",
            range:,
          )
        end

        context "#as_json" do
          test "only includes expected fields" do
            expected = {
              "type" => "MULTILINE",
              "start_path" => "README.md",
              "start_line" => 1,
              "start_commit_oid" => "deadbeef",
              "end_path" => "README.md",
              "end_line" => 2,
              "end_commit_oid" => "feebdaed",
            }
            assert_equal expected, @position.as_json
          end
        end
      end

      class FileTest < GitHub::TestCase
        setup do
          range = PullRequests::CommentPosition::Positions::DiffRange.new(
            base_commit_oid: "deadbeef",
            start_commit_oid: "deadbeef",
            end_commit_oid: "feebdaed",
          )
          @position = PullRequests::CommentPosition::Positions::File.new(
            path: "README.md",
            commit_oid: "deadbeef",
            range:,
          )
        end

        context "#as_json" do
          test "only includes expected fields" do
            expected = {
              "type" => "FILE",
              "path" => "README.md",
              "commit_oid" => "deadbeef",
            }
            assert_equal expected, @position.as_json
          end
        end
      end
    end
  end
end
