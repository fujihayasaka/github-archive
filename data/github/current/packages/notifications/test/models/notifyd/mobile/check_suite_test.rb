# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd::Mobile
  class NotifydCheckSuiteTest < GitHub::TestCase
    setup do
      make_trusted_oauth_apps_owner
      @repository = create(:repository)
      @check_suite = create(
        :check_suite_for_actions_app,
        :failure,
        :with_push,
        name: "Test suite",
        repository: @repository,
        head_repository: @repository,
        head_branch: "wip-branch",
        event: "pull_request",
      )
    end

    test "#render with a pull request" do
      issue = create(:issue, repository: @repository, title: "This code is awesome so we should merge it.")
      @repository.heads.create(@check_suite.head_branch, @check_suite.head_sha, @repository.owner)
      @pull_request = create(
        :pull_request,
        :disable_disk_access,  # so that we don't have to search within a real repo
        issue: issue,
        head_sha: @check_suite.head_sha,
        head_ref: @check_suite.head_branch,
        head_repository: @repository,
      )
      renderer = CheckSuiteRenderer.new(
        check_suite: @check_suite,
        repository: @repository,
        pull_request: @pull_request,
        attempt: 1
      )
      layout = renderer.render

      assert_equal "PR run failed", layout.title
      assert_equal @repository.name_with_display_owner, layout.subtitle
      assert_match /Test suite, Attempt #1 - This code is awesome so we should merge it\. \([a-z0-9]+\)/, layout.body
      assert_equal @check_suite.permalink, layout.url
      assert_equal @pull_request.permalink(include_host: false), layout.thread_id
      assert_equal "ci_activity", layout.thread_type
    end

    test "#render without a pull request" do
      renderer = CheckSuiteRenderer.new(
        check_suite: @check_suite,
        repository: @repository,
        pull_request: @nil,
        attempt: 1
      )
      layout = renderer.render

      assert_equal "Run failed", layout.title
      assert_equal @repository.name_with_display_owner, layout.subtitle
      assert_match /Test suite, Attempt #1 - wip-branch \([a-z0-9]+\)/, layout.body
      assert_equal @check_suite.permalink, layout.url
      assert_equal @check_suite.permalink(include_host: false), layout.thread_id
      assert_equal "ci_activity", layout.thread_type
    end
  end
end
