# typed: true
# frozen_string_literal: true

require "test_helper"

class MagicShellTest < GitHub::TestCase
  fixtures do
    @pub_user  = create(:user)

    @pub_repo   = create(:repository, owner: @pub_user,  pushed_at: Time.now - 2.hours, from_example: :mojombo_grit)
  end

  setup do
    GitHub.cache.allow = /magic_shell:v1:.*/
    GitHub.cache.clear
  end

  test "is able to call defined methods and cache data" do
    shell = MagicShell.new(@pub_user, @pub_repo)

    assert_query_count(1, ignore_feature_flags: true) do
      shell.open_repo_issue_count_for_viewer
    end

    # At this point, the data should be appropriately cached for this
    # viewer and repo, so we should not hit the database again.
    assert_query_count(0, ignore_feature_flags: true) do
      shell.open_repo_issue_count_for_viewer
    end
  end

  test "caches data for logged out (nil) viewer" do
    # It's valid for a viewer to be nil, and we can cache a value for logged out
    # users.
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    MagicShell::Strategies::AccessibilityLinkUnderlinesEnabled.any_instance.stubs(:can_use_precomputed_data?).returns(true)

    shell = MagicShell.new(nil, @pub_repo)

    shell.accessibility_link_underlines_enabled?
    assert_equal 1, GitHub.dogstats.increments("magic_shell.cache.miss", tags: ["strategy:MagicShell::Strategies::AccessibilityLinkUnderlinesEnabled", "context:viewer"]).size

    shell.accessibility_link_underlines_enabled?
    assert_equal 1, GitHub.dogstats.increments("magic_shell.cache.hit", tags: ["strategy:MagicShell::Strategies::AccessibilityLinkUnderlinesEnabled", "context:viewer"]).size
  end

  test "falls back to the gracefully degraded data when repository is nil " do
    # This test ensures that we do correctly gracefully degrade in the event
    # that a nil repository is passed to a repo specific strategy. This should
    # never happen in production because any repo-specific query will be
    # issued from a repo page, but we're not able to easily enforce that with
    # our static type checking due to how the abstract methods are defined. This
    # test is essentially a safeguard.
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    MagicShell::Strategies::OpenClassicProjectsCount.any_instance.stubs(:can_use_precomputed_data?).returns(true)

    assert_nothing_raised do
      MagicShell.new(@pub_user, nil).open_classic_projects_count
    end

    assert_equal 1, GitHub.dogstats.increments("magic_shell.gracefully_degraded", tags: ["strategy:MagicShell::Strategies::OpenClassicProjectsCount", "context:repository"]).size
  end

  test "emits dogstatsd metrics for cache hits and misses" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    shell = MagicShell.new(@pub_user, @pub_repo)

    shell.open_classic_projects_count
    assert_equal 1, GitHub.dogstats.increments("magic_shell.cache.miss", tags: ["strategy:MagicShell::Strategies::OpenClassicProjectsCount", "context:repository"]).size

    shell.open_classic_projects_count
    assert_equal 1, GitHub.dogstats.increments("magic_shell.cache.hit", tags: ["strategy:MagicShell::Strategies::OpenClassicProjectsCount", "context:repository"]).size
  end

  test "emits dogstatsd distribution for fallback code path" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    MagicShell::Strategies::OpenClassicProjectsCount.any_instance.stubs(:can_use_precomputed_data?).returns(false)

    shell = MagicShell.new(@pub_user, @pub_repo)

    shell.open_classic_projects_count
    assert_equal 1, GitHub.dogstats.distributions("magic_shell.fallback.duration", tags: ["strategy:MagicShell::Strategies::OpenClassicProjectsCount", "context:repository"]).size
  end

  test "emits dogstatsd distribution for precomputed code path" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    MagicShell::Strategies::OpenClassicProjectsCount.any_instance.stubs(:can_use_precomputed_data?).returns(true)

    shell = MagicShell.new(@pub_user, @pub_repo)

    shell.open_classic_projects_count
    assert_equal 1, GitHub.dogstats.distributions("magic_shell.precomputed.duration", tags: ["strategy:MagicShell::Strategies::OpenClassicProjectsCount", "context:repository"]).size
  end

  test "does not re-raise when a gracefully degradable exception occurs in a strategy outside of development" do
    GitHub::AppEnvironment.stubs(:development?).returns(false)
    shell = MagicShell.new(@pub_user, @pub_repo)

    MagicShell::Strategies::OpenRepoIssueCountForViewer.any_instance.stubs(:fetch_live_data).raises(StandardError)
    # The graceful degradation for this strategy is to return nil
    assert_nil shell.open_repo_issue_count_for_viewer
  end

  test "re-raises when a gracefully degradable exception occurs in a strategy in development" do
    GitHub::AppEnvironment.stubs(:development?).returns(true)
    shell = MagicShell.new(@pub_user, @pub_repo)

    MagicShell::Strategies::OpenRepoIssueCountForViewer.any_instance.stubs(:fetch_live_data).raises(StandardError)
    assert_raises StandardError do
      shell.open_repo_issue_count_for_viewer
    end
  end
end
