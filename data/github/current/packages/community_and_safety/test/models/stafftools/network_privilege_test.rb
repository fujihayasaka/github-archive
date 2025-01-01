# typed: true
# frozen_string_literal: true

require "test_helper"

class StafftoolsNetworkPrivilegeTest < GitHub::TestCase
  fixtures do
    @repo_hidden = create(:repository)
    @repo_visible = create(:repository)
    @repo_hidden_also = create(:repository)

    @repo_hidden.set_network_privilege(:hide_from_discovery, true)
    @repo_hidden_also.set_network_privilege(:hide_from_discovery, true)
  end

  context "hidden_from_discovery scope" do
    test "returns only network privileges where hide_from_discovery is true" do
      results = Stafftools::NetworkPrivilege.hidden_from_discovery.pluck(:repository_id)
      assert_same_elements [@repo_hidden.id, @repo_hidden_also.id], results
    end
  end

  test "queues jobs to recalculate trending repos when hiding from discovery" do
    disable_feature_flag(:skip_trending_repo_recalculation)

    assert_enqueued_with job: CalculateTrendingReposJob, args: ["daily"] do
      assert_enqueued_with job: CalculateTrendingReposJob, args: ["weekly"] do
        assert_enqueued_with job: CalculateTrendingReposJob, args: ["monthly"] do
          @repo_visible.set_network_privilege(:hide_from_discovery, true)
          Stafftools::NetworkPrivilege.recalculate_trending_repos
        end
      end
    end
  end

  test "queues jobs to recalculate trending repos when unhiding from discovery" do
    disable_feature_flag(:skip_trending_repo_recalculation)

    assert_enqueued_with job: CalculateTrendingReposJob, args: ["daily"] do
      assert_enqueued_with job: CalculateTrendingReposJob, args: ["weekly"] do
        assert_enqueued_with job: CalculateTrendingReposJob, args: ["monthly"] do
          @repo_hidden.set_network_privilege(:hide_from_discovery, false)
          Stafftools::NetworkPrivilege.recalculate_trending_repos
        end
      end
    end
  end

  test "does not enqueue trending repos job if hide_from_discovery not changed" do
    disable_feature_flag(:skip_trending_repo_recalculation)

    assert_no_enqueued_jobs(only: CalculateTrendingReposJob) do
      @repo_hidden.set_network_privilege(:collaborators_only, true)
    end
  end

  test "does not enqueue trending repos job if skip_trending_repo_recalculation is disabled" do
    enable_feature_flag(:skip_trending_repo_recalculation)

    assert_no_enqueued_jobs(only: CalculateTrendingReposJob) do
      @repo_hidden.set_network_privilege(:hide_from_discovery, false)
      Stafftools::NetworkPrivilege.recalculate_trending_repos
    end
  end
end
