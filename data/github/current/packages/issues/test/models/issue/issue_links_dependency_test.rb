# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueLinksDependencyTest < GitHub::TestCase
  include HydroTestHelpers
  include IssuesGraphTestHelpers
  include ConditionalAccess::FilterTestHelper
  include UnlockedRepositoryCheckTestHelper

  fixtures do
    @owner = create(:user)
    @repo = create(:private_repository, owner: @owner)
    @user = create(:user)
    @public_repo = create(:public_repository, owner: @user)
    @issue = create(:issue, repository: @repo, user: @owner)
    @public_issue = create(:issue, repository: @public_repo, user: @user)
    @public_issue2 = create(:issue, repository: @public_repo, user: @user)
    @tracked_issue = create(:issue, repository: @repo, user: @owner)

    create(:issue_link, source_issue: @issue, target_issue: @tracked_issue, link_type: :track)
    @closed_tracked_issue = create(:issue, state: :closed, repository: @repo)
    create(:issue_link, source_issue: @issue, target_issue: @closed_tracked_issue, link_type: :track)
    @closed_parent_issue = create(:issue, state: :closed, repository: @repo)
    create(:issue_link, source_issue: @closed_parent_issue, target_issue: @tracked_issue, link_type: :track)
    # a public issue is tracked in a private issue one
    create(:issue_link, source_issue: @tracked_issue, target_issue: @public_issue, link_type: :track)
    create(:issue_link, source_issue: @public_issue2, target_issue: @public_issue, link_type: :track)
  end

  setup do
    clear_memoized_unlocked_repository_check
  end

  context "associations" do
    test "tracked_issues" do
      assert_same_elements [@tracked_issue, @closed_tracked_issue], @issue.tracked_issues.to_a
    end

    test "tracked_in_issues" do
      assert_same_elements [@issue, @closed_parent_issue], @tracked_issue.tracked_in_issues
    end
  end

  context "tracked_issues_progress" do
    test "with preload" do
      @issue.tracked_issues.to_a
      assert_equal({ total: 2, completed: 1 }, @issue.tracked_issues_progress)
    end

    test "without preload" do
      assert_equal({ total: 2, completed: 1 }, @issue.tracked_issues_progress)
    end
  end

  test "tracking_issues_total_count" do
    assert_equal(2, @tracked_issue.tracking_issues_total_count)
  end

  test "displayable_tracking_issues_count filters out issues which are not accesible to the viewer" do
    assert_equal(1, @public_issue.displayable_tracking_issues_count(viewer: @user))
    assert_equal(2, @public_issue.displayable_tracking_issues_count(viewer: @owner))
  end

  test "displayable_tracking_issues_for" do
    assert_equal(@issue, @tracked_issue.displayable_tracking_issues_for(viewer: @owner).first)
    assert_equal(@closed_parent_issue, @tracked_issue.displayable_tracking_issues_for(viewer: @owner).last)
  end

  test "normalized_tracking_issues" do
    GitHub.flipper[:tasklist_block].enable
    GitHub.flipper[:issue_hierarchy_state].enable

    non_duplicate = create(:issue, repository: @repo, user: @owner)
    stub_tracking_issues(
      child: @tracked_issue,
      tracked_by: [non_duplicate, @issue] # @issue is already in the issue links table
    )

    # Wait for denormalized data to be used, rather than forced-normalized after write
    # https://github.com/github/github/commit/c6537782fabac28595bed0ce9fd3be505f3ea6fa
    Timecop.freeze(future = 10.minutes.from_now) do
      assert_equal 3, @tracked_issue.normalized_tracking_issues(viewer: @owner).size
      assert_equal non_duplicate.id, @tracked_issue.normalized_tracking_issues(viewer: @owner).first[:issue_id]
      assert_equal @issue.id, @tracked_issue.normalized_tracking_issues(viewer: @owner)[1][:issue_id]
      assert_equal @closed_parent_issue.id, @tracked_issue.normalized_tracking_issues(viewer: @owner)[2][:issue_id]
    end
  end

  test "normalized_tracking_issues respects cap_filter" do
    GitHub.flipper[:tasklist_block].enable
    GitHub.flipper[:issue_hierarchy_state].enable

    non_duplicate = create(:issue, repository: @repo, user: @owner)
    stub_tracking_issues(
      child: @tracked_issue,
      tracked_by: [non_duplicate, @issue] # @issue is already in the issue links table
    )

    result = @tracked_issue.normalized_tracking_issues(viewer: @owner, cap_filter: cap_unauthorizing_filter([@owner]))
    first, second = result
    assert_equal 2, result.size
    refute_includes result.map { |issue| issue[:issue_id] }, non_duplicate.id
    assert_equal @issue.id, first[:issue_id]
    assert_equal @closed_parent_issue.id, second[:issue_id]
  end

  context "has_tracked_issues?" do
    test "return true when tracked_issues exist" do
      issue = create(:issue)
      issue_link1 = create(:issue_link, source_issue: issue, link_type: :track)
      issue_link2 = create(:issue_link, source_issue: issue, link_type: :track)

      assert_predicate issue, :has_tracked_issues?
    end

    test "return false when no tracked_issues exist" do
      issue = create(:issue)

      refute_predicate issue, :has_tracked_issues?
    end
  end

  context "tracked issues operations" do
    test "fetching tracked_issues for an issue ordered by creation time" do
      issue = create(:issue)
      issue_link1 = Timecop.freeze(10.minutes.ago) { create(:issue_link, source_issue: issue) }
      issue_link2 = Timecop.freeze(5.minutes.ago) { create(:issue_link, source_issue: issue) }
      create(:issue_link)

      assert_equal 2, issue.tracked_issues.length
      assert_equal issue_link1.target_issue, issue.tracked_issues.first
      assert_equal issue_link2.target_issue, issue.tracked_issues.second
    end

    context "create batch" do
      context "validations" do
        test "do not create nested issues if no parameter is passed" do
          issue = create(:issue, repository: @public_repo, user: @user)

          issue.track_issues_batch(nil, @user)

          assert_equal 0, issue.tracked_issues.length
        end

        test "do not create nested issues if empty array is passed" do
          issue = create(:issue, repository: @public_repo, user: @user)

          issue.track_issues_batch([], @user)

          assert_equal 0, issue.tracked_issues.length
        end

        test "creating a batch of nested issues filters out PRs" do
          issue1 = create(:issue, repository: @public_repo, user: @user)
          issue2 = create(:issue, repository: @public_repo, user: @user)
          pr1 = create(:pull_request, :disable_disk_access, repository: @public_repo, user: @user)

          issue1.track_issues_batch([pr1.issue, issue2], @user)

          assert_equal 1, issue1.tracked_issues.length
        end

        test "creating a batch of nested issues filters out self references" do
          issue1 = create(:issue, repository: @public_repo)
          issue2 = create(:issue, repository: @public_repo)

          issue1.track_issues_batch([issue1, issue2], @user)

          assert_equal 1, issue1.tracked_issues.length
        end
      end

      context "permissions" do
        test "do not create nested issues if actor has no write permission to the source" do
          private_issue = create(:issue, repository: @repo, user: @owner)
          public_issue = create(:issue, repository: @public_repo, user: @user)

          private_issue.track_issues_batch([public_issue], @user)

          assert_equal 0, private_issue.tracked_issues.length
        end

        test "do not create nested issues if actor has no read permission to the target" do
          private_issue = create(:issue, repository: @repo, user: @owner)
          public_issue = create(:issue, repository: @public_repo, user: @user)

          public_issue.track_issues_batch([private_issue], @user)

          assert_equal 0, public_issue.tracked_issues.length
        end

        test "create nested issue when user has access to the source issue created by a different user" do
          owner_created_issue = create(:issue, repository: @public_repo, user: @owner)
          public_issue = create(:issue, repository: @public_repo, user: @user)

          owner_created_issue.track_issues_batch([public_issue], @user)

          assert_equal 1, owner_created_issue.tracked_issues.length
        end

        test "creates a nested issues in public repo if all permissions are correct" do
          private_repo1 = create(:private_repository, owner: @owner)
          private_repo2 = create(:private_repository, owner: @owner)
          private_issue1 = create(:issue, repository: private_repo1, user: @owner)
          private_issue2 = create(:issue, repository: private_repo2, user: @owner)
          public_issue = create(:issue, repository: @public_repo, user: @user)

          issue = create(:issue, repository: @public_repo, user: @user)

          # user cant's add owner's private issues
          issue.track_issues_batch([private_issue1, private_issue2, public_issue], @user)

          assert_equal 1, issue.tracked_issues.length
        end

        test "creates nested issues in private repo if all permissions are correct" do
          private_issue1 = create(:issue, repository: @repo, user: @owner)
          private_issue2 = create(:issue, repository: @repo, user: @owner)
          private_issue3 = create(:issue, repository: @repo, user: @owner)
          public_issue1 = create(:issue, repository: @public_repo, user: @user)
          public_issue2 = create(:issue, repository: @public_repo, user: @user)

          private_issue1.track_issues_batch([public_issue1, public_issue2], @owner)
          assert_equal 2, private_issue1.tracked_issues.length

          # owner can add their private issues
          private_issue1.track_issues_batch([private_issue2, private_issue3], @owner)

          assert_equal 4, private_issue1.tracked_issues.reload.length
        end
      end

      context "performance" do
        test "N of requests when actor has no write permissions to the source" do
          GitHub.flipper[:issues_graph_api].disable
          private_issue = create(:issue, repository: @repo, user: @owner)
          public_issue = create(:issue, repository: @public_repo, user: @user)

          # at most 2 queries for access checks (repo + parent abilitites) and repo unlocks
          # no insert
          expected_queries = GitHub.enterprise? ? 2 : 0
          assert_query_count(expected_queries, ignore_feature_flags: true) do
            private_issue.track_issues_batch([public_issue], @user)
          end
        end

        test "N of requests when actor is the owner of the source" do
          GitHub.flipper[:issues_graph_api].disable
          GitHub.flipper[:tasklist_block].disable

          public_issue = create(:issue, :with_instrumentation, :wait_for_orchestration, repository: @public_repo, user: @owner)
          private_issue2 = create(:issue, :with_instrumentation, :wait_for_orchestration, repository: @repo, user: @owner)
          private_issue3 = create(:issue, :with_instrumentation, :wait_for_orchestration, repository: @repo, user: @owner)
          private_issue4 = create(:issue, :with_instrumentation, :wait_for_orchestration, repository: @repo, user: @owner)

          # 1 insert
          assert_query_count(1, ignore_feature_flags: true) do
            public_issue.track_issues_batch([private_issue2, private_issue3, private_issue4], @owner)
          end

          assert_equal 3, public_issue.tracked_issues.length
        end

        test "creating a batch of nested issues makes as few SQL queries as possible" do
          GitHub.flipper[:issues_graph_api].disable
          GitHub.flipper[:tasklist_block].disable
          public_issue = create(:issue, repository: @public_repo, user: @owner)
          public_issue2 = create(:issue, repository: @public_repo, user: @user)
          public_issue3 = create(:issue, repository: @public_repo, user: @user)
          public_issue4 = create(:issue, repository: @public_repo, user: @user)
          private_issue1 = create(:issue, repository: @repo, user: @owner)
          private_issue2 = create(:issue, repository: @repo, user: @owner)

          # 4 queries for access checks (repo + user + abilities + parent abilitites)
          # 1 query for Ghost (if not cached)
          # 1 insert
          # 1 query for transactions
          # 1 query for repository_networks when sending the hydro message
          # 1 query for repository_unlocks (Enterprise only)
          assert_max_query_count(GitHub.enterprise? ? 9 : 8, ignore_feature_flags: true) do
            public_issue.track_issues_batch([public_issue2, private_issue1], @user)
          end

          assert_equal 1, public_issue.tracked_issues.length

          # 4 queries for access checks (repo + user + abilities + parent abilitites)
          # 1 query for Ghost (if not cached)
          # 1 insert
          # 1 query for transactions
          assert_max_query_count(7) do
            public_issue.track_issues_batch([public_issue3, public_issue4, private_issue1, private_issue2], @user)
          end

          assert_equal 3, public_issue.tracked_issues.reload.length
        end

        test "a bigger batch of xrepo issues do not increase number of SQL queries" do
          GitHub.flipper[:issues_graph_api].disable
          GitHub.flipper[:tasklist_block].disable
          private_repo1 = create(:private_repository, :full_creation, owner: @owner)
          private_repo2 = create(:private_repository, :full_creation, owner: @owner)
          private_repo3 = create(:private_repository, :full_creation, owner: @owner)
          private_repo4 = create(:private_repository, :full_creation, owner: @owner)
          private_repo5 = create(:private_repository, :full_creation, owner: @owner)
          private_issue1 = create(:issue, repository: private_repo1)
          private_issue2 = create(:issue, repository: private_repo2)
          private_issue3 = create(:issue, repository: private_repo3)
          private_issue4 = create(:issue, repository: private_repo4)
          private_issue5 = create(:issue, repository: private_repo5)
          public_issue = create(:issue, repository: @public_repo)

          issue = create(:issue, repository: @public_repo)

          # 4 queries for access checks (repo + user + abilities + parent abilitites)
          # 1 query for unlocked repositories checks (enterprise only)
          # 1 query for Ghost (if not cached)
          # 1 insert
          # 1 query for transactions
          # 1 query for repository_networks when sending the hydro message
          assert_max_query_count(GitHub.enterprise? ? 9 : 8, ignore_feature_flags: true) do
            issue.track_issues_batch([private_issue1, private_issue2, private_issue3, private_issue4, private_issue5, public_issue], @user)
          end

          assert_equal 1, issue.tracked_issues.length
        end
      end
    end

    context "delete batch" do
      context "validations" do
        test "do not delete nested issues if no parameter is passed" do
          public_issue = create(:issue, repository: @public_repo, user: @owner)
          private_issue = create(:issue, repository: @repo, user: @owner)
          create(:issue_link, source_issue: public_issue, target_issue: private_issue)

          public_issue.stop_tracking_batch(nil, @owner)

          assert_equal 1, public_issue.tracked_issues.length
        end

        test "do not delete nested issues if empty array is passed" do
          public_issue = create(:issue, repository: @public_repo, user: @owner)
          private_issue = create(:issue, repository: @repo, user: @owner)
          create(:issue_link, source_issue: public_issue, target_issue: private_issue)

          public_issue.stop_tracking_batch([], @owner)

          assert_equal 1, public_issue.tracked_issues.length
        end
      end

      context "permissions" do
        test "do not delete nested issues if actor has no write access to source issue" do
          public_issue = create(:issue, repository: @public_repo, user: @owner)
          private_issue = create(:issue, repository: @repo, user: @owner)
          create(:issue_link, source_issue: private_issue, target_issue: public_issue)

          # user has no access to owner's issue
          private_issue.stop_tracking_batch([public_issue], @user)

          assert_equal 1, private_issue.tracked_issues.length
        end

        test "deletes nested issues if actor has write access to source issue" do
          public_issue = create(:issue, repository: @public_repo, user: @owner)
          private_issue = create(:issue, repository: @repo, user: @owner)
          create(:issue_link, source_issue: private_issue, target_issue: public_issue)

          # owner has access to owner's issue
          private_issue.stop_tracking_batch([public_issue], @owner)

          assert_equal 0, private_issue.tracked_issues.length
        end

        test "deletes nested issues if actor has no read access to target issue but has write access to source" do
          public_issue = create(:issue, repository: @public_repo, user: @owner)
          private_issue = create(:issue, repository: @repo, user: @owner)
          create(:issue_link, source_issue: public_issue, target_issue: private_issue)

          # user has access to public_issue, but no read permission for private_issue
          public_issue.stop_tracking_batch([private_issue], @owner)

          assert_equal 0, public_issue.tracked_issues.length
        end
      end

      context "performance" do
        test "N of requests when actor has no write permissions to the source" do
          GitHub.flipper[:issues_graph_api].disable
          private_issue = create(:issue, repository: @repo, user: @owner)
          public_issue = create(:issue, repository: @public_repo, user: @user)
          create(:issue_link, source_issue: private_issue, target_issue: public_issue)

          assert_query_count(GitHub.enterprise? ? 1 : 0, ignore_feature_flags: true) do
            private_issue.stop_tracking_batch([public_issue], @user)
          end

          assert_equal 1, private_issue.tracked_issues.length
        end

        test "N of requests when actor is the owner of the source" do
          GitHub.flipper[:issues_graph_api].disable

          public_issue = create(:issue, :with_instrumentation, :wait_for_orchestration, repository: @public_repo, user: @owner)
          private_issue2 = create(:issue, :with_instrumentation, :wait_for_orchestration, repository: @repo, user: @owner)
          private_issue3 = create(:issue, :with_instrumentation, :wait_for_orchestration, repository: @repo, user: @owner)
          private_issue4 = create(:issue, :with_instrumentation, :wait_for_orchestration, repository: @repo, user: @owner)

          create(:issue_link, source_issue: public_issue, target_issue: private_issue2)
          create(:issue_link, source_issue: public_issue, target_issue: private_issue3)
          create(:issue_link, source_issue: public_issue, target_issue: private_issue4)

          # 1 insert
          assert_query_count(1, ignore_feature_flags: true) do
            public_issue.stop_tracking_batch([private_issue2, private_issue3, private_issue4], @owner)
          end

          assert_equal 0, public_issue.tracked_issues.length
        end

        test "deleting a batch of nested issues makes as few SQL queries as possible" do
          GitHub.flipper[:issues_graph_api].disable

          public_issue = create(:issue, :with_instrumentation, :wait_for_orchestration, repository: @public_repo, user: @owner)
          public_issue2 = create(:issue, :with_instrumentation, :wait_for_orchestration, repository: @public_repo, user: @owner)
          public_issue3 = create(:issue, :with_instrumentation, :wait_for_orchestration, repository: @public_repo, user: @owner)
          public_issue4 = create(:issue, :with_instrumentation, :wait_for_orchestration, repository: @public_repo, user: @owner)

          create(:issue_link, source_issue: public_issue, target_issue: public_issue2)
          create(:issue_link, source_issue: public_issue, target_issue: public_issue3)
          create(:issue_link, source_issue: public_issue, target_issue: public_issue4)

          # 1 delete, 1 repo unlocks check (Enterprise only)
          clear_memoized_unlocked_repository_check
          assert_query_count(GitHub.enterprise? ? 2 : 1, ignore_feature_flags: true) do
            public_issue.stop_tracking_batch([public_issue2], @user)
          end

          assert_equal 2, public_issue.tracked_issues.length

          # 1 delete
          assert_query_count(1, ignore_feature_flags: true) do
            public_issue.stop_tracking_batch([public_issue3, public_issue4], @owner)
          end

          assert_equal 0, public_issue.tracked_issues.reload.length
        end
      end
    end
  end

  unless GitHub.enterprise?
    context "Hydro instrumentation" do
      test "linking issue as a tracked issue publishes a hydro event" do
        issue1 = create(:issue, repository: @repo)
        issue2 = create(:issue, repository: @repo)

        issue1.track_issue(issue2, @owner)

        with_hydro_publisher(GitHub.low_latency_hydro_publisher) do

          assert_hydro_published({
            actor: Hydro::EntitySerializer.user(@owner),
            source_repository: Hydro::EntitySerializer.repository(issue1.repository),
            source_issue: Hydro::EntitySerializer.issue(issue1),
            target_repository: Hydro::EntitySerializer.repository(issue2.repository),
            target_issue: Hydro::EntitySerializer.issue(issue2),
            link_type: "SUBTASK",
            new_target_issue: false,
          }, schema: "github.v1.IssueLinkCreate")
        end
      end

      test "deleting tracked issue link publishes a hydro event" do
        issue1 = create(:issue, repository: @repo)
        issue2 = create(:issue, repository: @repo)
        issue_link = create(:issue_link, source_issue: issue1, target_issue: issue2)

        issue1.stop_tracking(issue2, @owner)

        with_hydro_publisher(GitHub.low_latency_hydro_publisher) do
          assert_hydro_published({
            actor: Hydro::EntitySerializer.user(@owner),
            source_repository: Hydro::EntitySerializer.repository(issue1.repository),
            source_issue: Hydro::EntitySerializer.issue(issue1),
            target_repository: Hydro::EntitySerializer.repository(issue2.repository),
            target_issue: Hydro::EntitySerializer.issue(issue2),
            link_type: "SUBTASK",
          }, schema: "github.v1.IssueLinkDelete")
        end
      end

      test "adding multiple issues as tracked_issues publishes a batch hydro event" do
        issue1 = create(:issue, repository: @repo)
        issue2 = create(:issue, repository: @repo)
        issue3 = create(:issue, repository: @repo)
        issue4 = create(:issue, repository: @public_repo)
        issue5 = create(:issue, repository: @public_repo)

        issue1.track_issues_batch([issue2, issue3, issue4, issue5], @owner)

        with_hydro_publisher(GitHub.low_latency_hydro_publisher) do

          assert_hydro_published({
            actor: Hydro::EntitySerializer.user(@owner),
            source_repository: Hydro::EntitySerializer.repository(issue1.repository),
            source_issue: Hydro::EntitySerializer.issue(issue1),
            total_issue_links: 4,
            xrepo_issue_links: 2,
            link_type: "SUBTASK"
          }, schema: "github.v1.IssueLinkBatchCreate")
        end
      end

      test "removing multiple issues as tracked_issues publishes a batch hydro event" do
        issue1 = create(:issue, repository: @repo)
        issue2 = create(:issue, repository: @repo)
        issue3 = create(:issue, repository: @repo)
        issue4 = create(:issue, repository: @public_repo)
        issue5 = create(:issue, repository: @public_repo)

        issue1.track_issues_batch([issue2, issue3, issue4, issue5], @owner)
        issue1.stop_tracking_batch([issue2, issue5], @owner)

        with_hydro_publisher(GitHub.low_latency_hydro_publisher) do

          assert_hydro_published({
            actor: Hydro::EntitySerializer.user(@owner),
            source_repository: Hydro::EntitySerializer.repository(issue1.repository),
            source_issue: Hydro::EntitySerializer.issue(issue1),
            total_issue_links: 2,
            xrepo_issue_links: 1,
            link_type: "SUBTASK"
          }, schema: "github.v1.IssueLinkBatchDelete")
        end
      end
    end
  end
end
