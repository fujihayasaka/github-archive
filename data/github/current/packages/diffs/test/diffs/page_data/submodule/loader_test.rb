# typed: true
# frozen_string_literal: true

require "test_helper"
require "json"

module Diffs
  module PageData::Submodule
    class LoaderTest < GitHub::TestCase
      include GitHub::QueryAssertionTestHelpers
      include PerformanceTestHelpers

      fixtures do
        @user = create(:user, login: "defunkt")
        @repository = create(:repository, owner: @user, from_example: :tree_with_submod)
        @submodule_repo = create(:repository, owner: @user, name: "ambition", from_example: :defunkt_ambition)

        commit = @repository.commits.find("0cfe649151423c706c93370994d6b1dad2698762")
        @commit_oid = commit.oid
        @diff_entry = commit.diff.entries.last.freeze
      end

      test "returns loader data for user with expected RPC calls" do
        expected_data = {
          "base_path" => "foo",
          "changed_files" => 2,
          "contents_url" => "/defunkt/ambition",
          "diff_entry" => @diff_entry,
          "path_link" => nil,
          "summary_deltas" => [],
        }

        rpc_counts = {
          authzd: {
            single: 0,
            batch: 0,
          },
          gitrpc: TestEnv.test_all_features? ? 1 : 2,
        }

        query_counts = {
          repositories: 1,
          repository_networks: 2,
        }

        assert_query_count_per_table(query_counts) do
          assert_rpc_calls(rpc_counts) do
            actual_data = Diffs::PageData::Submodule::Loader.load(
              diff_entry: @diff_entry,
              repository: @repository,
            )

            fail "Expected data to be present" if actual_data.nil?

            assert_equal expected_data["diff_entry"].path, actual_data.diff_entry.path
            assert_equal expected_data["diff_entry"].b_path, actual_data.diff_entry.b_path
            assert_equal expected_data["diff_entry"].a_path, actual_data.diff_entry.a_path
            assert_equal expected_data["diff_entry"].b_mode, actual_data.diff_entry.b_mode
            assert_equal expected_data["diff_entry"].a_mode, actual_data.diff_entry.a_mode
            assert_equal expected_data["diff_entry"].b_blob, actual_data.diff_entry.b_blob
            assert_equal expected_data["diff_entry"].a_blob, actual_data.diff_entry.a_blob

            assert_equal expected_data["base_path"], actual_data.base_path
            assert_equal expected_data["changed_files"], actual_data.changed_files
            assert_equal expected_data["contents_url"], actual_data.contents_url
            assert_nil actual_data.path_link # TODO - figure out how to test this, it is not being set in the test
            assert_equal 2, actual_data.summary_deltas.length
          end
        end
      end
    end
  end
end
