# typed: true
# frozen_string_literal: true

require "test_helper"

module Diffs
  module PageData::SummaryDelta
    class PayloadTest < GitHub::TestCase
      include PerformanceTestHelpers

      test "serializes the summary delta payload with Ruby conventions without RPC/sql calls" do
        @expected_payload = {
          "linesAdded" => 1,
          "linesDeleted" => 0,
          "path" => "foo",
          "pathDigest" => "2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae",
          "status" => "ADDED"
        }

        summary_delta = GitRPC::Diff::Summary::Delta.new(
          status: "A",
          similarity: 0,
          additions: 1,
          deletions: 0,
          old_file: {
            oid: "0000000000000000000000000000000000000000",
            mode: "000000",
            path: "foo"
          },
          new_file: {
            oid: "e73ad092fb3730260f0738b6df1cfd8b432d840d",
            mode: "120000",
            path: "foo"
          }
        )

        rpc_counts = {
          authzd: {
            single: 0,
            batch: 0,
          },
          gitrpc: 0,
        }

        assert_no_queries do
          assert_rpc_calls(rpc_counts) do
            actual_payload = Diffs::PageData::SummaryDelta::Payload.call(summary_delta)
            assert_equal @expected_payload.as_json, actual_payload.as_json
          end
        end
      end
    end
  end
end
