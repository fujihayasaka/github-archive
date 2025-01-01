# rubocop:todo Sorbet/TrueSigil
# typed: false
# frozen_string_literal: true

require "test_helper"

class PullRequestCodeScanningDependencyTest < GitHub::TestCase
  include GitHub::PullRequestTestHelpers

  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user, from_example: :pull_request_fork)
    example_repo_snapshot

    @pull_request = make_pr(@repo, @repo).tap(&:create_merge_commit)

    make_trusted_oauth_apps_owner
    @integration = create(:code_scanning_integration)

    @check_suite = create(:check_suite,
      repository: @repo,
      github_app: @integration,
      head_sha: @pull_request.head_sha,
    )
    @check_run = create(:check_run, repository: @repo, check_suite: @check_suite)
    @check_suite.update!(status: "completed", conclusion: "success")

    @code_scanning_check_suite = create(:code_scanning_check_suite,
      check_suite: @check_suite,
      pull_request_ref: @pull_request.merge_ref,
      pull_request_sha: @pull_request.merge_commit_sha)

    create(
      :code_scanning_review_comment,
      repository: @repo,
      pull_request: @pull_request,
      pull_request_review_comment: create(:pull_request_review_comment, pull_request: @pull_request),
      alert_number: 5
    )
  end

  setup do
    example_repo_restore
  end

  test "code_scanning_latest_check_suite" do
    refute_nil @pull_request.code_scanning_latest_check_suite
  end

  context "async preloading of code scanning alerts" do
    test "async_preload_code_scanning_alerts" do
      promise = nil
      body_params_matcher = VCRMatchers.request_body_json_matches(repositoryId: @repo.id.to_s, numbers: [5], headCommitOid: @pull_request.head_sha, mergeCommitOid: @pull_request.merge_commit_sha)
      VCR.use_cassette("code-scanning/annotations", persist_with: :turboscan, match_requests_on: [:method, :uri, body_params_matcher]) do
        promise = @pull_request.async_preload_code_scanning_alerts
        promise.sync
      end

      assert_max_query_count(0) do
        assert_equal "CodeQL", promise.sync.first.result.tool.name
      end
    end

    test "async_code_scanning_alerts_cached! raises if no preloaded" do
      assert_raises(PullRequest::CodeScanningDependency::NonPreloadedAlerts) do
        @pull_request.async_code_scanning_alerts_cached!
      end

      VCR.use_cassette("code-scanning/annotations", persist_with: :turboscan, match_requests_on: [:method, :uri]) do
        @pull_request.async_preload_code_scanning_alerts
      end

      refute_nil @pull_request.async_code_scanning_alerts_cached!.sync
    end

    test "async_preload_code_scanning_alerts returns nil when code_scanning_check_suite does not exist" do
      @code_scanning_check_suite.destroy!
      assert_nil @pull_request.async_preload_code_scanning_alerts.sync
    end

    test "async_preload_code_scanning_alerts caches the promise" do
      VCR.use_cassette("code-scanning/annotations", persist_with: :turboscan, match_requests_on: [:method, :uri]) do
        @pull_request.async_preload_code_scanning_alerts.sync
      end

      assert_max_query_count(0) do
        assert_equal "CodeQL", @pull_request.async_preload_code_scanning_alerts.sync.first.result.tool.name
      end
    end
  end
end

class PullRequestCodeScanningDependencyAutofixTest < GitHub::TestCase
  include GitHub::PullRequestTestHelpers

  fixtures do
    GitHub::Enterprise.ensure_business!
    @owner = create(:organization)
    @repo = create(:private_repository, owner: @owner, from_example: :pull_request_fork)

    @pull_request = make_pr(@repo, @repo).tap(&:create_merge_commit)

    make_trusted_oauth_apps_owner
    @integration = create(:code_scanning_integration)

    @check_suite = create(:check_suite,
      repository: @repo,
      github_app: @integration,
      head_sha: @pull_request.head_sha,
    )
    @check_run = create(:check_run, repository: @repo, check_suite: @check_suite)
    @check_suite.update!(status: "completed", conclusion: "success")

    @code_scanning_check_suite = create(:code_scanning_check_suite,
      check_suite: @check_suite,
      pull_request_ref: @pull_request.merge_ref,
      pull_request_sha: @pull_request.merge_commit_sha
    )

    create(
      :code_scanning_review_comment,
      repository: @repo,
      pull_request: @pull_request,
      pull_request_review_comment: create(:pull_request_review_comment, pull_request: @pull_request),
      alert_number: 5
    )
  end

  setup do
    CodeScanning::Autofix.stubs(:available_in_environment?).returns(true)
    @owner.mark_advanced_security_as_purchased_for_entity(actor: @owner.admins.first)
    @repo.enable_advanced_security(actor: @owner.admins.first)
  end

  context "async preloading of code scanning autofix suggestions" do
    test "async_preload_code_scanning_suggested_fixes" do
      promise = nil
      body_params_matcher = VCRMatchers.request_body_json_matches(
        repositoryId: @repo.id.to_s,
        headCommitOid: @pull_request.head_sha,
        alertNumbers: [5],
        refNamesBytes: @pull_request.build_ref_names_bytes_for_code_scanning_suggested_fix.map { |r| Base64.strict_encode64(r) }
      )
      VCR.use_cassette("code-scanning/get-suggested-fix", persist_with: :turboscan, match_requests_on: [:method, :uri, body_params_matcher]) do
        promise = @pull_request.async_preload_code_scanning_suggested_fixes
      end

      description = "To fix this vulnerability, we need to remove the logging of sensitive information, specifically the `password` variable on line 99. The best way to fix this vulnerability is to simply remove the `console.log` statement that logs the sensitive data.\n"
      assert_max_query_count(0) do
        assert_equal description, promise.sync.suggested_fix_alerts[2].suggested_fix.description
      end
    end

    test "async_code_scanning_suggested_fixes_cached! raises if not preloaded" do
      assert_raises(PullRequest::CodeScanningDependency::NonPreloadedSuggestedFixes) do
        @pull_request.async_code_scanning_suggested_fixes_cached!
      end

      VCR.use_cassette("code-scanning/get-suggested-fix", persist_with: :turboscan, match_requests_on: [:method, :uri]) do
        @pull_request.async_preload_code_scanning_suggested_fixes
      end

      refute_nil @pull_request.async_code_scanning_suggested_fixes_cached!.sync
    end

    test "async_preload_code_scanning_suggested_fixes caches the promise" do
      VCR.use_cassette("code-scanning/get-suggested-fix", persist_with: :turboscan, match_requests_on: [:method, :uri]) do
        @pull_request.async_preload_code_scanning_suggested_fixes.sync
      end

      description = "To fix this vulnerability, we need to remove the logging of sensitive information, specifically the `password` variable on line 99. The best way to fix this vulnerability is to simply remove the `console.log` statement that logs the sensitive data.\n"
      assert_max_query_count(0) do
        assert_equal description, @pull_request.async_preload_code_scanning_suggested_fixes.sync.suggested_fix_alerts[2].suggested_fix.description
      end
    end

    test "async_preload_code_scanning_fixes_alerts returns an empty map/hash if Autofix is disabled" do
      CodeScanningRepositoryConfig.new(@repo).disable_code_scanning_autofix_settings(actor: @owner.admins.first)

      VCR.use_cassette("code-scanning/get-suggested-fix", persist_with: :turboscan, match_requests_on: [:method, :uri]) do
        assert @pull_request.async_preload_code_scanning_suggested_fixes.sync.suggested_fix_alerts.respond_to?(:[])
        assert_equal({}, @pull_request.async_preload_code_scanning_suggested_fixes.sync.suggested_fix_alerts.to_h)
      end
    end
  end
end
