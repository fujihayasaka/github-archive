# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  class KVTest < GitHub::TestCase
    context ".for_repository" do
      test "returns KV instances scoped to the given repos" do
        kv1 = PullRequests::KV.for_repository(repo(id: 1))
        kv2 = PullRequests::KV.for_repository(repo(id: 2))

        kv1.set("only1", "example")
        kv2.set("only2", "example")
        kv1.set("both", "value1")
        kv2.set("both", "value2")

        assert_equal "example", kv1.get("only1").value { nil }
        assert_nil kv1.get("only2").value { nil }
        assert_equal "value1", kv1.get("both").value { nil }

        assert_nil kv2.get("only1").value { nil }
        assert_equal "example", kv2.get("only2").value { nil }
        assert_equal "value2", kv2.get("both").value { nil }

        kv1.del("both")

        refute kv1.exists("both").value!
        assert kv2.exists("both").value!
      end
    end

    context ".dual_write_for_repository" do
      test "can write to both the global KV store and the issues-pull-requests store" do
        repo = repo(id: 1)
        global_kv = GitHub.kv # rubocop:todo GitHub/DoNotUseGlobalKv
        ipr_kv = PullRequests::KV.for_repository(repo)
        dual_kv = PullRequests::KV.dual_write_for_repository(
          repo,
          feature_flag_prefix: :pull_requests_kv_test,
        )

        # Uses global KV by default
        disable_feature_flag(:pull_requests_kv_test_dual_write)
        disable_feature_flag(:pull_requests_kv_test_write_to_target)

        dual_kv.set("pr_dual_kv_test_default", "example")
        assert global_kv.exists("pr_dual_kv_test_default").value!
        refute ipr_kv.exists("pr_dual_kv_test_default").value!

        # Can write to both stores
        enable_feature_flag(:pull_requests_kv_test_dual_write)
        disable_feature_flag(:pull_requests_kv_test_write_to_target)

        dual_kv.set("pr_dual_kv_test_both", "example")
        assert global_kv.exists("pr_dual_kv_test_both").value!
        assert ipr_kv.exists("pr_dual_kv_test_both").value!

        # Can write to only the IPR store
        disable_feature_flag(:pull_requests_kv_test_dual_write)
        enable_feature_flag(:pull_requests_kv_test_write_to_target)

        dual_kv.set("pr_dual_kv_test_target", "example")
        refute global_kv.exists("pr_dual_kv_test_target").value!
        assert ipr_kv.exists("pr_dual_kv_test_target").value!
      end
    end

    private

    def repo(id:)
      build_stubbed(:repository, id:)
    end
  end
end
