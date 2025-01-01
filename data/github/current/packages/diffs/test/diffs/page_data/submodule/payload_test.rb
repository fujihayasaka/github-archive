# typed: true
# frozen_string_literal: true

require "test_helper"

module Diffs
  module PageData::Submodule
    class PayloadTest < GitHub::TestCase
      include PerformanceTestHelpers

      fixtures do
        @user = create(:user, login: "defunkt")
        @repository = create(:repository, owner: @user, from_example: :tree_with_submod)
        @submodule_repo = create(:repository, owner: @user, name: "ambition", from_example: :defunkt_ambition)

        commit = @repository.commits.find("0cfe649151423c706c93370994d6b1dad2698762")
        @commit_oid = commit.oid
        @diff_entry = commit.diff.entries.last.freeze
      end

      test "serializes the submodule payload with Ruby conventions without RPC/sql calls" do
        @expected_payload = {
            "basePath" => "foo",
            "changedFiles" => 2,
            "contentsUrl" => "/defunkt/ambition",
            "newCommitOid" => "1f7ca369fa616f1e1be920e8b79a8071f984e79f",
            "oldCommitOid" => "909e4d4f706c11cafbe35fd9729dc6cce24d6d6f",
            "status" => "MODIFIED",
            "submoduleUrl" => nil,
            "summary" => [
              {
                "linesAdded" => 1,
                "linesDeleted" => 2,
                "path" => "lib/ambition/query.rb",
                "pathDigest" =>
                "38972033df67dfb7c3cbd563c1ffe56327ae9b5cf9d21528fd1cb6ce34e800ce",
                "status" => "MODIFIED"
              },
              {
                "linesAdded" => 0,
                "linesDeleted" => 13,
                "path" => "test/join_test.rb",
                "pathDigest" =>
                "cd81bf524e5b38a06c64657cf6f9825f4b0e2014438c4057bee24dcbcdb0218f",
                "status" => "MODIFIED"
              }
            ]
          }

        data = Diffs::PageData::Submodule::Loader.load(
          diff_entry: @diff_entry,
          repository: @repository,
        )

        fail "Expected data to be present" if data.nil?

        rpc_counts = {
          authzd: {
            single: 0,
            batch: 0,
          },
          gitrpc: 0,
        }

        assert_no_queries do
          assert_rpc_calls(rpc_counts) do
            actual_payload = Diffs::PageData::Submodule::Payload.call(data)
            assert_equal @expected_payload.as_json, actual_payload.as_json
          end
        end
      end
    end
  end
end
