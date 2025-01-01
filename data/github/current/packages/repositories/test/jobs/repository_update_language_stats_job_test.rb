# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryUpdateLanguageStatsJobTest < GitHub::TestCase
  include GitHub::LoggerHelper

  fixtures do
    @repo = create(:repository)
  end

  test "only one job of each type is enqueued concurrently" do
    assert_enqueued_jobs 1, queue: "languages" do
      repo_id = 1
      3.times { RepositoryUpdateLanguageStatsJob.perform_later(repo_id) }
    end
  end

  test "returns nil on a GitRPC::Protocol::DGit::ResponseError" do
    Repository.any_instance.stubs(:analyze_languages).raises(GitRPC::Protocol::DGit::ResponseError, "test error")
    expected_payload = {
      "exception.message" => "test error",
      "code.namespace" => "RepositoryUpdateLanguageStatsJob",
      "code.function" => "perform",
      "gh.repo.id" => @repo.id
    }
    assert_logged(**expected_payload) do
      result = RepositoryUpdateLanguageStatsJob.perform_now(@repo.id)
      assert_nil result
    end
  end

  test "sets tenant context for Proxima" do
    # mimic the situation where the tenant is not set
    GitHub::CurrentTenant.remove
    assert_nil GitHub::CurrentTenant.get
    refute_predicate GitHub::CurrentTenant, :unscoped?
    refute @repo.owner

    RepositoryUpdateLanguageStatsJob.perform_now(@repo.id)

  end if TestEnv.test_in_multitenancy_mode?
end
