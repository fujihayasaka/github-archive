# typed: true
# frozen_string_literal: true

# fixed: true
require "test_helper"

class Issue::IssuesGraphDependencyTest < GitHub::TestCase
  include DogstatsTestHelpers
  include IssuesGraphTestHelpers

  fixtures do
    @issue = create(:issue, state: "open")
    @repo = create(:repository, owner: @issue.user)
    @pull_request = create(:pull_request, :merged, :disable_disk_access, repository: @repo)
  end

  setup do
    disable_feature_flag(:issues_graph_api)
    disable_feature_flag(:issues_graph_api_disable_denormalized_read)
    enable_feature_flag(:issues_graph_api_concurrent_faraday)
    disable_feature_flag(:tasklist_block)
    disable_feature_flag(:tasklist_block_markdown_at_rest)
    enable_feature_flag(:issue_hierarchy_state)
    @issue_as_hierarchy_model = @issue.to_hierarchy_model
  end

  context "remote_tracking_blocks" do
    test "returns false when a new record" do
      issue = build(:issue)

      refute_predicate issue, :persisted?
      assert_equal false, issue.remote_tracking_blocks
    end

    test "returns false when repository has tracking blocks disabled" do
      repository = create(:repository)
      disable_feature_flag(:tasklist_block, repository.owner)
      issue = create(:issue, repository: repository)

      assert_predicate issue, :persisted?
      refute repository.owner.feature_enabled?(:tasklist_block), "tasklist_block should not be enabled for repository owner"
      assert_equal false, issue.remote_tracking_blocks
    end

    test "calls tracking blocks api when repository has tracking blocks enabled" do
      repository = create(:repository)
      enable_feature_flag(:tasklist_block, repository.owner)
      enable_feature_flag(:issues_graph_api_concurrent_faraday)
      issue = create(:issue, repository: repository)

      assert_predicate issue, :persisted?
      assert repository.owner.feature_enabled?(:tasklist_block), "tasklist_block should not be enabled for repository owner"

      GitHub.async_issues_graph_api_client.expects(:get_issue).once.returns(
        Promise.resolve(
          ::IssuesGraph::Result.success(
            ::IssuesGraph::Proto::GetIssueResponse.new
          )
        )
      )
      issue.remote_tracking_blocks
    end

    test "calls tracking blocks api with sync client when repository has concurrent faraday disabled" do
      repository = create(:repository)
      enable_feature_flag(:tasklist_block, repository.owner)
      enable_feature_flag(:issue_hierarchy_state)
      disable_feature_flag(:issues_graph_api_concurrent_faraday)
      issue = create(:issue, repository: repository)

      assert_predicate issue, :persisted?
      assert repository.owner.feature_enabled?(:tasklist_block), "tasklist_block should not be enabled for repository owner"

      GitHub.issues_graph_api_client_strict.expects(:get_issue).once.returns(
        ::IssuesGraph::Result.success(
          ::IssuesGraph::Proto::GetIssueResponse.new
        )
      )
      issue.remote_tracking_blocks
    end

    test "sorts tracking blocks by order property" do
      repository = create(:repository)
      enable_feature_flag(:tasklist_block, repository.owner)
      enable_feature_flag(:issue_hierarchy_state)
      disable_feature_flag(:issues_graph_api_concurrent_faraday)
      issue = create(:issue, repository: repository)

      assert_predicate issue, :persisted?
      assert repository.owner.feature_enabled?(:tasklist_block), "tasklist_block should not be enabled for repository owner"

      tracking_issue = IssuesGraph::Proto::Issue.new(
        key: IssuesGraph::Proto::Key.new(itemId: 50),
        userName: "login",
        repoName: "name",
        number: 1,
        repoId: 1,
        title: "tracked issue",
        url: "http://dummy-url.github.com/login/name/issues/1",
        state: "open",
      )
      tracking_block_1 = IssuesGraph::Proto::TrackingBlock.new(
        name: "list 1", order: 100, issues: [tracking_issue]
      )
      tracking_block_2 = IssuesGraph::Proto::TrackingBlock.new(
        name: "list 2", order: 200, issues: [tracking_issue]
      )
      tracking_block_3 = IssuesGraph::Proto::TrackingBlock.new(
        name: "list 3", order: 300, issues: [tracking_issue]
      )
      tracking_block_response = IssuesGraph::Proto::GetIssueResponse.new(
        tracking: [
          # These are intentionally out of order to exercise the sorting logic
          tracking_block_2,
          tracking_block_3,
          tracking_block_1
        ]
      )

      GitHub.issues_graph_api_client_strict.expects(:get_issue).once.returns(
        ::IssuesGraph::Result.success(tracking_block_response)
      )

      expected_blocks = [
        tracking_block_1,
        tracking_block_2,
        tracking_block_3
      ]
      result_blocks = issue.remote_tracking_blocks
      assert_equal expected_blocks, result_blocks
    end
  end

  context "hierarchy_state" do
    test "stats and logs skipped metric when issue is a new record" do
      issue = build(:issue)

      assert_predicate issue, :new_record?
      assert_difference 'GitHub.dogstats.increments("issues.hierarchy.state.sync", tags: ["result:skipped", "reason:new_record"]).count' do
        issue.hierarchy_state
      end
    end

    test "stats and logs skipped metric when feature flag is disabled" do
      repository = create(:repository)
      disable_feature_flag(:tasklist_block, repository.owner)
      enable_feature_flag(:issues_graph_api_disable_denormalized_read, repository)
      issue = create(:issue, repository: repository)

      refute_predicate issue, :tasklist_blocks_enabled?
      assert_difference 'GitHub.dogstats.increments("issues.hierarchy.state.sync", tags: ["result:skipped", "reason:feature_flag"]).count' do
        issue.hierarchy_state
      end
    end

    test "stats and logs error metric when twirp returns an non-not found error" do
      repository = create(:repository)
      enable_feature_flag(:tasklist_block, repository.owner)
      enable_feature_flag(:issue_hierarchy_state)
      enable_feature_flag(:issues_graph_api_concurrent_faraday)
      enable_feature_flag(:issues_graph_api_disable_denormalized_read, repository)
      issue = create(:issue, repository: repository)

      result = ::IssuesGraph::Result.error(Twirp::Error.unknown("Could not fetch issue"))
      GitHub.async_issues_graph_api_client.expects(:get_issue).once.returns(Promise.resolve(result))

      assert_difference 'GitHub.dogstats.increments("issues.hierarchy.state.sync", tags: ["result:error", "code:unknown"]).count' do
        issue.hierarchy_state
      end
    end

    test "stats and logs not_found metric when twirp returns a not found error" do
      repository = create(:repository)
      enable_feature_flag(:tasklist_block, repository.owner)
      enable_feature_flag(:issue_hierarchy_state)
      enable_feature_flag(:issues_graph_api_concurrent_faraday)
      enable_feature_flag(:issues_graph_api_disable_denormalized_read, repository)
      issue = create(:issue, repository: repository)

      result = ::IssuesGraph::Result.error(Twirp::Error.not_found("GetIssue: issue with ID 1 not found"))
      GitHub.async_issues_graph_api_client.expects(:get_issue).once.returns(Promise.resolve(result))

      assert_difference 'GitHub.dogstats.increments("issues.hierarchy.state.sync", tags: ["result:error", "code:not_found"]).count' do
        issue.hierarchy_state
      end
    end

    test "stats and logs error metric when faraday returns an error" do
      repository = create(:repository)
      enable_feature_flag(:tasklist_block, repository.owner)
      enable_feature_flag(:issue_hierarchy_state)
      enable_feature_flag(:issues_graph_api_concurrent_faraday)
      enable_feature_flag(:issues_graph_api_disable_denormalized_read, repository)
      issue = create(:issue, repository: repository)

      # Mock issues-graph service error response
      result = ::IssuesGraph::Result.error(::Twirp::Error.canceled("Timeout"))
      GitHub.async_issues_graph_api_client.expects(:get_issue).once.returns(Promise.resolve(result))

      assert_difference 'GitHub.dogstats.increments("issues.hierarchy.state.sync", tags: ["result:error", "code:canceled"]).count' do
        issue.hierarchy_state
      end
    end

    test "stats and logs success metric" do
      repository = create(:repository)
      enable_feature_flag(:tasklist_block, repository.owner)
      enable_feature_flag(:issue_hierarchy_state)
      enable_feature_flag(:issues_graph_api_concurrent_faraday)
      enable_feature_flag(:issues_graph_api_disable_denormalized_read, repository)
      issue = create(:issue, repository: repository)

      tracking_block_response = IssuesGraph::Proto::GetIssueResponse.new(tracking: [])
      result = ::IssuesGraph::Result.success(tracking_block_response)
      GitHub.async_issues_graph_api_client.expects(:get_issue).once.returns(Promise.resolve(result))

      assert_difference 'GitHub.dogstats.increments("issues.hierarchy.state.sync", tags: ["result:success"]).count' do
        issue.hierarchy_state
      end
    end

    test "hierarchy_state returns nil when feature flag disabled" do
      repository = create(:repository)
      enable_feature_flag(:tasklist_block, repository.owner)
      disable_feature_flag(:issue_hierarchy_state)
      disable_feature_flag(:issues_graph_api_concurrent_faraday)
      enable_feature_flag(:issues_graph_api_disable_denormalized_read, repository)
      issue = create(:issue, repository: repository)

      assert_nil issue.hierarchy_state
    end
  end

  context "async_hierarchy_state" do
    test "calls get_issue with denormalized data disabled when issue has been very recently modified" do
      viewer = create(:user)
      repository = create(:repository)
      enable_feature_flag(:tasklist_block, repository.owner)
      enable_feature_flag(:issue_hierarchy_state)
      issue = create(:issue, repository: repository)

      assert_predicate issue, :persisted?

      GitHub.async_issues_graph_api_client.expects(:get_issue).once.with(
        use_denormalized_data: false,
        key: IssuesGraph::Proto::Key.new(
          ownerId: repository.owner_id,
          itemId: issue.id,
        )
      )

      issue.async_hierarchy_state(viewer: viewer)
    end

    test "calls get_issue with denormalized data enabled when issue has not been very recently modified" do
      viewer = create(:user)
      repository = create(:repository)
      enable_feature_flag(:tasklist_block, repository.owner)
      enable_feature_flag(:issue_hierarchy_state)
      issue = create(:issue, repository: repository)

      assert_predicate issue, :persisted?

      GitHub.async_issues_graph_api_client.expects(:get_issue).once.with(
        use_denormalized_data: true,
        key: IssuesGraph::Proto::Key.new(
          ownerId: repository.owner_id,
          itemId: issue.id,
        )
      )

      Timecop.freeze(future = 10.minutes.from_now) do
        issue.async_hierarchy_state(viewer: viewer)
      end
    end

    test "calls get_issue with denormalized data enabled when feature is disabled for repository" do
      repository = create(:repository)
      enable_feature_flag(:tasklist_block, repository.owner)
      enable_feature_flag(:issue_hierarchy_state)
      issue = create(:issue, repository: repository)

      assert_predicate issue, :persisted?

      GitHub.async_issues_graph_api_client.expects(:get_issue).once.with(
        use_denormalized_data: true,
        key: IssuesGraph::Proto::Key.new(
          ownerId: repository.owner_id,
          itemId: issue.id,
        )
      )

      Timecop.freeze(future = 10.minutes.from_now) do
        issue.async_hierarchy_state
      end
    end

    test "calls get_issue with denormalized data disabled when feature is enabled for repository owner and issue has not been very recently modified" do
      repository = create(:repository)
      enable_feature_flag(:tasklist_block, repository.owner)
      enable_feature_flag(:issue_hierarchy_state)
      enable_feature_flag(:issues_graph_api_disable_denormalized_read, repository)
      issue = create(:issue, repository: repository)

      assert_predicate issue, :persisted?

      GitHub.async_issues_graph_api_client.expects(:get_issue).once.with(
        use_denormalized_data: false,
        key: IssuesGraph::Proto::Key.new(
          ownerId: repository.owner_id,
          itemId: issue.id,
        )
      )

      Timecop.freeze(future = 10.minutes.from_now) do
        issue.async_hierarchy_state
      end
    end

    test "calls get_issue with denormalized data disabled when feature is disabled for repository but enabled for viewer and issue has not been very recently modified" do
      viewer = create(:user)
      repository = create(:repository)
      enable_feature_flag(:tasklist_block, repository.owner)
      enable_feature_flag(:issue_hierarchy_state)
      disable_feature_flag(:issues_graph_api_disable_denormalized_read, repository)
      enable_feature_flag(:issues_graph_api_disable_denormalized_read, viewer)
      issue = create(:issue, repository: repository)

      assert_predicate issue, :persisted?

      GitHub.async_issues_graph_api_client.expects(:get_issue).once.with(
        use_denormalized_data: false,
        key: IssuesGraph::Proto::Key.new(
          ownerId: repository.owner_id,
          itemId: issue.id,
        )
      )

      Timecop.freeze(future = 10.minutes.from_now) do
        issue.async_hierarchy_state(viewer: viewer)
      end
    end
  end

  context "hierarchy_tracked_by" do
    test "returns empty array when a new record" do
      issue = build(:issue)

      refute_predicate issue, :persisted?
      assert_equal [], issue.hierarchy_tracked_by
    end

    test "returns empty array when repository has tracking blocks disabled" do
      repository = create(:repository)
      disable_feature_flag(:tasklist_block, repository.owner)
      issue = create(:issue, repository: repository)

      assert_predicate issue, :persisted?
      refute repository.owner.feature_enabled?(:tasklist_block), "tasklist_block should not be enabled for repository owner"
      assert_equal [], issue.hierarchy_tracked_by
    end

    test "calls tracking blocks api when repository has tracking blocks enabled" do
      repository = create(:repository)
      enable_feature_flag(:tasklist_block, repository.owner)
      enable_feature_flag(:issue_hierarchy_state)
      enable_feature_flag(:issues_graph_api_concurrent_faraday)
      issue = create(:issue, repository: repository)

      assert_predicate issue, :persisted?
      assert repository.owner.feature_enabled?(:tasklist_block), "tasklist_block should not be enabled for repository owner"

      result = ::IssuesGraph::Result.success(
        ::IssuesGraph::Proto::GetIssueResponse.new
      )
      GitHub.async_issues_graph_api_client
        .expects(:get_issue).once
        .returns(Promise.resolve(result))
      issue.hierarchy_tracked_by
    end

    test "returns deduplicated list of tracked-in issues" do
      repository = create(:repository)
      enable_feature_flag(:tasklist_block, repository.owner)
      enable_feature_flag(:issue_hierarchy_state)
      enable_feature_flag(:issues_graph_api_concurrent_faraday)
      issue = create(:issue, repository: repository)

      assert_predicate issue, :persisted?
      assert repository.owner.feature_enabled?(:tasklist_block), "tasklist_block should not be enabled for repository owner"

      tracking_issue = IssuesGraph::Proto::Issue.new(
        key: IssuesGraph::Proto::Key.new(itemId: 50),
        userName: "login",
        repoName: "name",
        number: 1,
        repoId: 1,
        title: "tracked issue",
        url: "http://dummy-url.github.com/login/name/issues/1",
        state: "open",
      )
      tracking_block = IssuesGraph::Proto::TrackingBlock.new(issues: [tracking_issue])
      tracking_block_2 = IssuesGraph::Proto::TrackingBlock.new(issues: [tracking_issue])
      tracking_block_response = IssuesGraph::Proto::GetIssueResponse.new(trackedBy: [tracking_block, tracking_block_2])
      result = ::IssuesGraph::Result.success(tracking_block_response)
      GitHub.async_issues_graph_api_client.expects(:get_issue).once.with(
        has_entries(
          use_denormalized_data: false,
          key: IssuesGraph::Proto::Key.new(
            ownerId: repository.owner_id,
            itemId: issue.id,
          )
        )
      ).returns(Promise.resolve(result))

      assert_equal 1, issue.hierarchy_tracked_by.size
    end

    test "returns list of tracked-in issues with tasklist blocks without parents filtered out" do
      repository = create(:repository)
      enable_feature_flag(:tasklist_block, repository.owner)
      enable_feature_flag(:issue_hierarchy_state)
      enable_feature_flag(:issues_graph_api_concurrent_faraday)
      issue = create(:issue, repository: repository)

      assert_predicate issue, :persisted?
      assert repository.owner.feature_enabled?(:tasklist_block), "tasklist_block should not be enabled for repository owner"

      tracking_issue = IssuesGraph::Proto::Issue.new(
        key: IssuesGraph::Proto::Key.new(itemId: -1),
        repoId: -1,
        userName: "login",
        repoName: "name",
        number: 1,
        title: "tracked issue",
        url: "http://dummy-url.github.com/login/name/issues/1",
        state: "open",
        itemType: "ISSUE",
      )
      tracking_block = IssuesGraph::Proto::TrackingBlock.new(issues: [tracking_issue])
      tracking_block_2 = IssuesGraph::Proto::TrackingBlock.new(issues: [])
      tracking_block_response = IssuesGraph::Proto::GetIssueResponse.new(trackedBy: [tracking_block, tracking_block_2])
      result = ::IssuesGraph::Result.success(tracking_block_response)
      GitHub.async_issues_graph_api_client.expects(:get_issue).once.with(
        use_denormalized_data: false,
        key: IssuesGraph::Proto::Key.new(
          ownerId: repository.owner_id,
          itemId: issue.id,
        )
      ).returns(Promise.resolve(result))

      assert_equal 1, issue.hierarchy_tracked_by.size
    end

    test "returns list of tracked-in issues with empty issues filtered out" do
      repository = create(:repository)
      enable_feature_flag(:tasklist_block, repository.owner)
      enable_feature_flag(:issue_hierarchy_state)
      enable_feature_flag(:issues_graph_api_concurrent_faraday)
      issue = create(:issue, repository: repository)

      assert_predicate issue, :persisted?
      assert repository.owner.feature_enabled?(:tasklist_block), "tasklist_block should not be enabled for repository owner"

      tracking_issue = IssuesGraph::Proto::Issue.new(
        key: IssuesGraph::Proto::Key.new(itemId: 0),
        repoId: 0,
        userName: "login",
        repoName: "name",
        number: 1,
        title: "tracked issue",
        url: "http://dummy-url.github.com/login/name/issues/1",
        state: "open",
      )
      tracking_block = IssuesGraph::Proto::TrackingBlock.new(issues: [tracking_issue])
      tracking_block_response = IssuesGraph::Proto::GetIssueResponse.new(trackedBy: [tracking_block])
      result = ::IssuesGraph::Result.success(tracking_block_response)
      GitHub.async_issues_graph_api_client.expects(:get_issue).once.with(
        has_entries(
          use_denormalized_data: false,
          key: IssuesGraph::Proto::Key.new(
            ownerId: repository.owner_id,
            itemId: issue.id,
          )
        )
      ).returns(Promise.resolve(result))

      assert_equal 0, issue.hierarchy_tracked_by.size
    end
  end

  context "reconcile_tracking_blocks" do
    test "does get invoked when tracking blocks are added to issue on create" do
      user = create(:user, login: "tracking")
      repository = create(:repository, owner: user, name: "blocks")
      enable_feature_flag(:tasklist_block)
      enable_feature_flag(:issue_hierarchy_state)
      assert repository.owner.feature_enabled?(:tasklist_block), "repository should have tasklist_block enabled"

      # Mock issues-graph service response
      primary_key = IssuesGraph::Proto::PrimaryKey.new(uuid: SecureRandom.uuid)
      add_tracking_block_response = ::IssuesGraph::Proto::AddTrackingBlockResponse.new(primaryKeys: [primary_key])
      add_tracking_block_result = ::IssuesGraph::Result.success(add_tracking_block_response)
      GitHub.issues_graph_api_client.stubs(:add_tracking_block_for_parent).returns(add_tracking_block_result)

      key = IssuesGraph::Proto::Key.new(primaryKey: primary_key)
      tracked_issue = IssuesGraph::Proto::Issue.new(userName: "tracking", repoName: "blocks", number: 1)
      tracking_block = IssuesGraph::Proto::TrackingBlock.new(key: key, name: "Tracking", issues: [tracked_issue])
      get_issue_response = IssuesGraph::Proto::GetIssueResponse.new(tracking: [tracking_block])
      get_issue_result = ::IssuesGraph::Result.success(get_issue_response)
      GitHub.async_issues_graph_api_client.stubs(:get_issue).returns(Promise.resolve(get_issue_result))

      body = <<~MD
      ## My tracking block

      ```[tasklist]
      - [ ] #1
      ```
      MD
      issue = build(:issue, repository: repository, user: user, body: body, state: "open")
      assert_predicate issue, :tracking_blocks_added?
      assert_predicate issue, :tasklist_blocks_enabled?
      assert issue.save!
    end

    test "replaces tracking blocks on save when tracking blocks are added to issue" do
      user = create(:user, login: "tracking")
      repository = create(:repository, name: "blocks")
      enable_feature_flag(:tasklist_block, repository.owner)
      enable_feature_flag(:issue_hierarchy_state)
      disable_feature_flag(:issues_graph_api_concurrent_faraday)
      enable_feature_flag(:issue_tasklist_block_writes)
      assert repository.owner.feature_enabled?(:tasklist_block), "repository should have tasklist_block enabled"

      GitHub.issues_graph_api_client.expects(:add_tracking_block_for_parent).returns(
        ::IssuesGraph::Result.success(
          ::IssuesGraph::Proto::AddTrackingBlockResponse.new(
            primaryKeys: [IssuesGraph::Proto::PrimaryKey.new(uuid: "test")]
          )
        )
      )

      body = <<~MD
      ## My tracking block

      ```[tasklist]
      - [ ] #1
      ```
      MD
      issue = build(:issue, repository: repository, user: user, body: body, state: "open")
      assert_predicate issue, :tracking_blocks_added?
      assert_predicate issue, :tasklist_blocks_enabled?
      assert issue.save!

      expected_body = <<~MD
      ## My tracking block

      https://github.com/#{repository.name_with_display_owner}/issues/1#tasklist-block-test
      MD

      assert_equal expected_body.squish, issue.body.squish
    end

    test "stats and logs metrics for tracking blocks on save" do
      user = create(:user, login: "tracking")
      repository = create(:repository, owner: user, name: "blocks")
      enable_feature_flag(:tasklist_block, repository.owner)
      enable_feature_flag(:issue_hierarchy_state)
      enable_feature_flag(:issue_tasklist_block_writes)
      assert repository.owner.feature_enabled?(:tasklist_block), "repository should have tasklist_block enabled"

      # Mock issues-graph service response
      primary_key = IssuesGraph::Proto::PrimaryKey.new(uuid: "test")
      data = ::IssuesGraph::Proto::AddTrackingBlockResponse.new(primaryKeys: [primary_key])
      result = ::IssuesGraph::Result.success(data)
      GitHub.issues_graph_api_client.expects(:add_tracking_block_for_parent).once.returns(result)

      child_issue = create(:issue, repository: repository, user: user)

      body = <<~MD
      ## My tracking block

      ```[tasklist]
      - [ ] ##{child_issue.number}
      - [ ] Draft issue
      - [ ] Second draft issue
      ```
      MD
      issue = build(:issue, repository: repository, user: user, body: body, state: "open")
      assert_predicate issue, :tracking_blocks_added?
      assert_predicate issue, :tasklist_blocks_enabled?

      assert_difference 'GitHub.dogstats.distributions("issues.tracking_blocks.reconcile.count").count' do
        assert_difference 'GitHub.dogstats.distributions("issues.tracking_blocks.reconcile.time").count' do
          assert_difference 'GitHub.dogstats.increments("issues.tracking_blocks.reconcile.item", tags: ["action:create", "subject:issue"]).count' do
            assert_difference 'GitHub.dogstats.increments("issues.tracking_blocks.reconcile.item", tags: ["action:create", "subject:draft_issue"]).count', 2 do
              assert issue.save!
            end
          end
        end
      end
    end

    test "logs and tracks metrics for empty tracking blocks" do
      user = create(:user)
      repository = create(:repository, owner: user)
      enable_feature_flag(:tasklist_block, repository.owner)
      enable_feature_flag(:issue_hierarchy_state)
      enable_feature_flag(:issue_tasklist_block_writes)
      assert repository.owner.feature_enabled?(:tasklist_block), "repository should have tasklist_block enabled"

      body = <<~MD
      ## My tracking block
      ```
      MD
      issue = create(:issue, repository: repository, user: user, body: body)

      assert_difference 'GitHub.dogstats.increments("issues.tracking_blocks.reconcile.empty").count' do
        issue.reconcile_tracking_blocks
      end
    end

    test "does get invoked when tracking blocks are added to issue on update" do
      user = create(:user, login: "tracking")
      repository = create(:repository, owner: user, name: "blocks")
      enable_feature_flag(:tasklist_block, repository.owner)
      enable_feature_flag(:issue_hierarchy_state)
      disable_feature_flag(:issues_graph_api_concurrent_faraday)
      assert repository.owner.feature_enabled?(:tasklist_block), "repository should have tasklist_block enabled"

      # Mock issues-graph service response for creating tracking block
      primary_key = IssuesGraph::Proto::PrimaryKey.new(uuid: SecureRandom.uuid)
      add_tracking_block_response = ::IssuesGraph::Proto::AddTrackingBlockResponse.new(primaryKeys: [primary_key])
      add_tracking_block_result = ::IssuesGraph::Result.success(add_tracking_block_response)
      GitHub.issues_graph_api_client.stubs(:add_tracking_block_for_parent).returns(add_tracking_block_result)
      remote_tracking_block_response = ::IssuesGraph::Proto::StatusResponse.new(success: true)
      remove_tracking_block_result = ::IssuesGraph::Result.success(remote_tracking_block_response)
      GitHub.issues_graph_api_client.stubs(:remove_tracking_block).returns(remove_tracking_block_result)

      body = <<~MD
      ## My missing tracking block
      MD
      issue = build(:issue, repository: repository, user: user, body: body, number: 1)
      refute_predicate issue, :tracking_blocks_added?
      assert_predicate issue, :tasklist_blocks_enabled?
      assert issue.save!

      # Mock issues-graph service response for rendering HTML
      key = IssuesGraph::Proto::Key.new(primaryKey: primary_key)
      tracked_issue = IssuesGraph::Proto::Issue.new(userName: "tracking", repoName: "blocks", number: 1)
      tracking_block = IssuesGraph::Proto::TrackingBlock.new(key: key, name: "Tracking", issues: [tracked_issue])
      get_issue_response = IssuesGraph::Proto::GetIssueResponse.new(tracking: [tracking_block])
      get_issue_result = ::IssuesGraph::Result.success(get_issue_response)
      GitHub.async_issues_graph_api_client.stubs(:get_issue).returns(Promise.resolve(get_issue_result))

      body = <<~MD
      ## My tracking block

      ```[tasklist]
      - [ ] #1
      ```
      MD
      assert issue.update_body(body, issue.user)
    end

    test "does not get invoked when there are no tracking blocks in the issue" do
      user = create(:user)
      repository = create(:repository, owner: user)
      enable_feature_flag(:tasklist_block, repository.owner)
      enable_feature_flag(:issue_hierarchy_state)
      assert repository.owner.feature_enabled?(:tasklist_block), "repository should have tasklist_block enabled"

      # Mock issues-graph service response
      GitHub.issues_graph_api_client.expects(:add_tracking_block_for_parent).never

      body = <<~MD
      ## My regular issue
      MD
      issue = build(:issue, repository: repository, user: user, body: body)
      refute_predicate issue, :tracking_blocks_added?
      assert_predicate issue, :tasklist_blocks_enabled?
      assert issue.save!
    end

    test "does not get invoked when tracking blocks are not enabled" do
      repository = create(:repository)
      disable_feature_flag(:tasklist_block, repository)
      refute repository.owner.feature_enabled?(:tasklist_block), "repository should not have tasklist_block enabled"

      GitHub.issues_graph_api_client.expects(:add_tracking_block_for_parent).never

      body = <<~MD
      ## My tracking block

      ```[tasklist]
      - [ ] #1
      ```
      MD
      issue = build(:issue, repository: repository, body: body)
      refute_predicate issue, :tracking_blocks_added?
      refute_predicate issue, :tasklist_blocks_enabled?
      assert issue.save!
    end

    test "tracks metrics when feature flag disabled on repository" do
      user = create(:user)
      repository = create(:repository, owner: user)
      refute repository.owner.feature_enabled?(:tasklist_block), "repository should not have tasklist_block enabled"
      enable_feature_flag(:issue_tasklist_block_writes)

      body = <<~MD
      ## My tracking block

      ```[tasklist]
      - [ ] #1
      - [ ] Draft issue
      - [ ] Second draft issue
      ```
      MD
      issue = create(:issue, repository: repository, body: body)

      assert_difference 'GitHub.dogstats.increments("issues.tracking_blocks.reconcile.disabled", tags: ["reason:feature_flag", "subject:owner"]).count' do
        issue.reconcile_tracking_blocks
      end
    end
  end

  context "reconcile_removed_tasklist_urls" do
    test "deletes tracking blocks when URLs are removed from issue body" do
      user = create(:user, login: "tracking")
      repository = create(:repository, owner: user, name: "blocks")
      enable_feature_flag(:tasklist_block, repository.owner)
      enable_feature_flag(:issue_hierarchy_state)
      enable_feature_flag(:issues_graph_api_concurrent_faraday)
      enable_feature_flag(:issue_tasklist_block_writes)

      removed_uuid_1 = "01234567-abcd-ef01-b719-a6ec3f0ccf52"
      removed_uuid_2 = "abcdef01-abcd-ef01-b719-867530900000"
      retained_uuid = "decafbad-abcd-ef01-b719-a6ec3f0ccf52"

      issue = create(:issue, user: user, repository: repository)

      tracking_blocks = [removed_uuid_1, retained_uuid, removed_uuid_2].map do |uuid|
        IssuesGraph::Proto::TrackingBlock.new(
          key: IssuesGraph::Proto::Key.new(
            primaryKey: IssuesGraph::Proto::PrimaryKey.new(uuid: uuid)
          )
        )
      end
      tracking_block_response = IssuesGraph::Proto::GetIssueResponse.new(tracking: tracking_blocks)
      result = ::IssuesGraph::Result.success(tracking_block_response)
      GitHub.async_issues_graph_api_client.expects(:get_issue).at_least_once.at_most(2).with(
        has_entries(
          use_denormalized_data: false,
          key: IssuesGraph::Proto::Key.new(
            ownerId: repository.owner_id,
            itemId: issue.id,
          ),
        ),
      ).returns(Promise.resolve(result))

      GitHub.issues_graph_api_client
        .expects(:remove_tracking_block).once
        .with(issue.owner.id, issue.id, removed_uuid_1, optionally(includes(:stat_tags)))
        .returns(::IssuesGraph::Result.success([]))
      GitHub.issues_graph_api_client
        .expects(:remove_tracking_block).once
        .with(issue.owner.id, issue.id, removed_uuid_2, optionally(includes(:stat_tags)))
        .returns(::IssuesGraph::Result.success([]))
      GitHub.issues_graph_api_client
        .expects(:remove_tracking_block)
        .never.with(issue.owner.id, issue.id, retained_uuid, optionally(includes(:stat_tags)))
        .returns(::IssuesGraph::Result.success([]))

      body = <<~MD
      ## My tracking blocks

      https://github.com/tracking/blocks/issues/1#tasklist-block-#{retained_uuid}

      Foo bar baz
      MD

      assert_difference 'GitHub.dogstats.distributions("issues.tracking_blocks.removed.count").count' do
        assert issue.update_body(body, issue.user)
      end
    end

    test "deletes tracking blocks when issue body is empty" do
      user = create(:user, login: "tracking")
      repository = create(:repository, owner: user, name: "blocks")
      enable_feature_flag(:tasklist_block, repository.owner)
      enable_feature_flag(:issue_hierarchy_state)
      enable_feature_flag(:issues_graph_api_concurrent_faraday)
      enable_feature_flag(:issue_tasklist_block_writes)

      removed_uuid_1 = "01234567-abcd-ef01-b719-a6ec3f0ccf52"
      removed_uuid_2 = "abcdef01-abcd-ef01-b719-867530900000"

      issue = create(:issue, user: user, repository: repository, body: "foo bar baz")

      tracking_blocks = [removed_uuid_1, removed_uuid_2].map do |uuid|
        IssuesGraph::Proto::TrackingBlock.new(
          key: IssuesGraph::Proto::Key.new(
            primaryKey: IssuesGraph::Proto::PrimaryKey.new(uuid: uuid)
          )
        )
      end
      tracking_block_response = IssuesGraph::Proto::GetIssueResponse.new(tracking: tracking_blocks)
      result = ::IssuesGraph::Result.success(tracking_block_response)
      GitHub.async_issues_graph_api_client.expects(:get_issue).once.with(
        use_denormalized_data: false,
        key: IssuesGraph::Proto::Key.new(
          ownerId: repository.owner_id,
          itemId: issue.id,
        )
      ).returns(Promise.resolve(result))

      GitHub.issues_graph_api_client
        .expects(:remove_tracking_block).once
        .with(issue.owner.id, issue.id, removed_uuid_1, optionally(includes(:stat_tags)),
        ).returns(::IssuesGraph::Result.success([]))
      GitHub.issues_graph_api_client
        .expects(:remove_tracking_block).once
        .with(issue.owner.id, issue.id, removed_uuid_2, optionally(includes(:stat_tags)))
        .returns(::IssuesGraph::Result.success([]))

      assert_difference 'GitHub.dogstats.distributions("issues.tracking_blocks.removed.count").count' do
        assert issue.update_body("", issue.user)
      end
    end
  end

  context "#tasklist_blocks_enabled?" do
    test "returns true when tracking blocks are enabled on repository" do
      repository = create(:repository)
      enable_feature_flag(:tasklist_block, repository.owner)
      issue = create(:issue, repository: repository)

      assert_predicate issue, :tasklist_blocks_enabled?
    end

    test "returns false when tracking blocks are disabled on repository" do
      repository = create(:repository)
      disable_feature_flag(:tasklist_block, repository.owner)
      issue = create(:issue, repository: repository)

      refute_predicate issue, :tasklist_blocks_enabled?
    end

    test "returns false when repo owner does not exist" do
      repository = create(:repository)
      enable_feature_flag(:tasklist_block)
      issue = create(:issue, repository: repository)
      repository.stubs(:owner).returns(nil)

      refute_predicate issue, :tasklist_blocks_enabled?
    end
  end

  context "#tracking_blocks_added?" do
    test "returns true when tracking blocks are enabled and added to issue body on create" do
      repository = create(:repository)
      enable_feature_flag(:tasklist_block, repository.owner)
      assert repository.owner.feature_enabled?(:tasklist_block), "repository have tasklist_block enabled"

      # Mock issues-graph service response
      primary_key = IssuesGraph::Proto::PrimaryKey.new(uuid: SecureRandom.uuid)
      add_tracking_block_response = ::IssuesGraph::Proto::AddTrackingBlockResponse.new(primaryKeys: [primary_key])
      add_tracking_block_result = ::IssuesGraph::Result.success(add_tracking_block_response)
      GitHub.issues_graph_api_client.stubs(:add_tracking_block_for_parent).returns(add_tracking_block_result)

      key = IssuesGraph::Proto::Key.new(primaryKey: primary_key)
      tracked_issue = IssuesGraph::Proto::Issue.new(userName: "tracking", repoName: "blocks", number: 1)
      tracking_block = IssuesGraph::Proto::TrackingBlock.new(key: key, name: "Tracking", issues: [tracked_issue])
      get_issue_response = IssuesGraph::Proto::GetIssueResponse.new(tracking: [tracking_block])
      get_issue_result = ::IssuesGraph::Result.success(get_issue_response)
      GitHub.async_issues_graph_api_client.stubs(:get_issue).returns(Promise.resolve(get_issue_result))

      body = <<~MD
      ## My tracking block

      ```[tasklist]
      - [ ] #1
      ```
      MD
      issue = build(:issue, repository: repository, body: body, state: "open")
      assert_predicate issue, :tracking_blocks_added?
      assert_predicate issue, :tasklist_blocks_enabled?
      assert issue.save!
    end

    test "returns true when tracking blocks are enabled and added to issue body on update" do
      repository = create(:repository)
      enable_feature_flag(:tasklist_block, repository.owner)
      assert repository.owner.feature_enabled?(:tasklist_block), "repository have tasklist_block enabled"

      body = <<~MD
      ## My empty tracking block
      MD
      issue = create(:issue, repository: repository, body: body)
      refute_predicate issue, :tracking_blocks_added?
      assert_predicate issue, :tasklist_blocks_enabled?

      body = <<~MD
      ## My empty tracking block

      ```[tasklist]
      - [ ] #1
      ```
      MD
      issue.body = body
      assert_predicate issue, :tracking_blocks_added?
    end

    test "returns false when tracking blocks are enabled and none are added to issue body on update" do
      repository = create(:repository)
      enable_feature_flag(:tasklist_block, repository.owner)
      disable_feature_flag(:issues_graph_api_concurrent_faraday)
      assert repository.owner.feature_enabled?(:tasklist_block), "repository have tasklist_block enabled"

      body = <<~MD
      ## My empty tracking block
      MD
      issue = create(:issue, repository: repository, body: body)
      refute_predicate issue, :tracking_blocks_added?
      assert_predicate issue, :tasklist_blocks_enabled?
      GitHub.issues_graph_api_client_strict.expects(:get_issue).once.returns(
        build_get_issue_success_response
      )

      body = <<~MD
      ## My other empty tracking block
      MD
      assert issue.update_body(body, issue.user)
      refute_predicate issue, :tracking_blocks_added?
    end

    test "returns false when tracking blocks are disabled on repository and added to issue body on create" do
      repository = create(:repository)
      disable_feature_flag(:tasklist_block, repository.owner)
      refute repository.owner.feature_enabled?(:tasklist_block), "repository should not have tasklist_block enabled"

      body = <<~MD
      ## My empty tracking block
      MD
      issue = build(:issue, repository: repository, body: body)
      refute_predicate issue, :tracking_blocks_added?
      refute_predicate issue, :tasklist_blocks_enabled?
    end

    test "returns false when tracking blocks are disabled on repository and added to issue body on update" do
      repository = create(:repository)
      disable_feature_flag(:tasklist_block, repository.owner)
      refute repository.owner.feature_enabled?(:tasklist_block), "repository should not have tasklist_block enabled"

      body = <<~MD
      ## My empty tracking block
      MD
      issue = create(:issue, repository: repository, body: body)
      refute_predicate issue, :tasklist_blocks_enabled?

      body = <<~MD
      ## My empty tracking block

      ```[tasklist]
      - [ ] #1
      ```
      MD
      issue.body = body
      refute_predicate issue, :tracking_blocks_added?
    end
  end

  context "#has_tasklist_blocks?" do
    test "returns false when tracking blocks exist in body but tasklist_block feature flag has not been enabled for repository owner" do
      repository = create(:repository)
      refute repository.owner.feature_enabled?(:tasklist_block), "repository owner should not have tasklist_block enabled"

      body = <<~MD
      ## My tracking block

      ```[tasklist]
      - [ ] #1
      ```
      MD
      issue = create(:issue, repository: repository, body: body)
      refute_predicate issue, :has_tasklist_blocks?
    end

    test "returns true when tracking blocks exist in body and features enabled for repository owner" do
      repository = create(:repository)
      enable_feature_flag(:tasklist_block, repository.owner)
      assert repository.owner.feature_enabled?(:tasklist_block), "repository owner should have tasklist_block enabled"

      body = <<~MD
      ## My tracking block

      ```[tasklist]
      - [ ] #1
      ```
      MD
      issue = build(:issue, repository: repository, body: body, state: "open")
      assert_predicate issue, :has_tasklist_blocks?
    end

    test "returns false when no tracking blocks exist in body and features enabled for repository owner" do
      repository = create(:repository)
      enable_feature_flag(:tasklist_block, repository.owner)
      assert repository.owner.feature_enabled?(:tasklist_block), "repository owner should have tasklist_block enabled"

      # Mock issues-graph service response
      primary_key = IssuesGraph::Proto::PrimaryKey.new(uuid: SecureRandom.uuid)
      add_tracking_block_response = ::IssuesGraph::Proto::AddTrackingBlockResponse.new(primaryKeys: [primary_key])
      add_tracking_block_result = ::IssuesGraph::Result.success(add_tracking_block_response)
      GitHub.issues_graph_api_client.stubs(:add_tracking_block_for_parent).returns(add_tracking_block_result)

      key = IssuesGraph::Proto::Key.new(primaryKey: primary_key)
      tracked_issue = IssuesGraph::Proto::Issue.new(userName: "tracking", repoName: "blocks", number: 1)
      tracking_block = IssuesGraph::Proto::TrackingBlock.new(key: key, name: "Tracking", issues: [tracked_issue])
      get_issue_response = IssuesGraph::Proto::GetIssueResponse.new(tracking: [tracking_block])
      get_issue_result = ::IssuesGraph::Result.success(get_issue_response)
      GitHub.async_issues_graph_api_client.stubs(:get_issue).returns(Promise.resolve(get_issue_result))

      body = <<~MD
      ## My non tracking block issue
      MD
      issue = create(:issue, repository: repository, body: body)
      refute_predicate issue, :has_tasklist_blocks?
    end
  end

  context "#reconcile_tracking_blocks_after_save" do
    test "when tasklist blocks are not enabled, it stats" do
      issue = build(:issue)
      enable_feature_flag(:issue_tasklist_block_writes)
      issue.stubs(:tasklist_blocks_enabled?).returns(false)

      issue.reconcile_tracking_blocks_after_save

      assert_dogstats_increment(1, "issues.tracking_blocks.reconcile.disabled")
    end

    test "when tasklist blocks are enabled, it stats" do
      enable_feature_flag(:tasklist_block)
      enable_feature_flag(:issue_tasklist_block_writes)
      assert_predicate @issue, :tasklist_blocks_enabled?

      @issue.reconcile_tracking_blocks_after_save

      assert_dogstats_distribution(1, "issues.tracking_blocks.reconcile.time")
    end

    test "when tasklist blocks are enabled, updates issues graph when all tasklist blocks have been removed" do
      enable_feature_flag(:tasklist_block)
      enable_feature_flag(:tasklist_block_markdown_at_rest)
      enable_feature_flag(:issue_tasklist_block_writes)
      assert_predicate @issue, :tasklist_blocks_enabled?
      @issue.stubs(:has_tasklist_blocks?).returns(false)

      GitHub.issues_graph_api_client.expects(:replace_tracking_blocks_for_parent)
      @issue.reconcile_tracking_blocks_after_save
    end
  end

  context "#sync_issues_graph_data" do
    test "calls out to the issues graph service to update issue title" do
      enable_feature_flag(:issues_graph_api)

      expected = @issue_as_hierarchy_model.merge(title: "New Title")
      SyncIssueToIssuesGraphJob.expects(:perform_later).with(expected)

      @issue.update(title: "New Title")
    end

    test "does not run if flag is off when updating title" do
      disable_feature_flag(:issues_graph_api)

      SyncIssueToIssuesGraphJob.expects(:perform_later).never

      @issue.update(title: "New Title")
    end

    test "does not run if title is not changed" do
      SyncIssueToIssuesGraphJob.expects(:perform_later).never

      @issue.update(body: "new body")
    end

    test "calls out to the issues graph service to update issue state" do
      enable_feature_flag(:issues_graph_api)

      expected = @issue_as_hierarchy_model.merge(state: "closed")
      SyncIssueToIssuesGraphJob.expects(:perform_later).with(expected)

      @issue.update(state: "closed")
    end

    test "does not run if flag is off when updating state" do
      disable_feature_flag(:issues_graph_api)

      SyncIssueToIssuesGraphJob.expects(:perform_later).never

      @issue.update(state: "closed")
    end

    test "does not run if state is not changed" do
      SyncIssueToIssuesGraphJob.expects(:perform_later).never

      @issue.update(body: "new body")
    end
  end
end

class IssueHierarchyModelTest < GitHub::TestCase
  include IssuesGraphTestHelpers
  include GitHub::LoggerHelper

  fixtures do
    user = create(:user)
    repo = create(:repository, owner: user)
    @issue = create(:issue, repository: repo, title: "issue title", body: "issue body", user: user)
    @pull_request = create(:pull_request, :merged, :disable_disk_access, repository: repo)
  end
  test "#to_hierarchy_model_key" do

    result = @issue.to_hierarchy_model_key

    assert_equal @issue.repository.owner_id, result[:ownerId]
    assert_equal @issue.id, result[:itemId]
  end

  test "#to_hierarchy_model" do
    result = @issue.to_hierarchy_model

    assert_equal @issue.repository.owner_id, result.dig(:key, :ownerId)
    assert_equal @issue.repository_id, result[:repoId]
    assert_equal @issue.id, result.dig(:key, :itemId)
    assert_equal @issue.title, result[:title]
    assert_equal @issue.url, result[:url]
    assert_equal @issue.state, result[:state]
    assert_nil   result[:stateReason]
    assert_equal @issue.number, result[:number]
    assert_equal @issue.repository.name, result[:repoName]
    assert_equal @issue.repository.owner.login, result[:userName]
    assert_equal "ISSUE", result[:itemType]
  end

  test "#to_hierarchy_model includes state and state_reason" do
    @issue.close(@issue.user, attributes: { state_reason: "not_planned" })

    result = @issue.to_hierarchy_model

    assert_equal @issue.repository.owner_id, result.dig(:key, :ownerId)
    assert_equal @issue.id, result.dig(:key, :itemId)
    assert_equal @issue.state, result[:state]
    assert_equal @issue.state_reason, result[:stateReason]
  end

  test "#to_hierarchy_model includes assignees of the issue" do
    user = create(:user)
    repo = create(:repository)
    create(:collaborator, collaborator: user, repository: repo)
    issue = create(:issue, repository: repo, assignee: user)

    result = issue.to_hierarchy_model

    assert_equal user.to_hierarchy_model, result.dig(:assignees, 0)
  end

  test "#to_hierarchy_model includes labels of the issue" do
    label = create(:label, repository: @issue.repository)
    @issue.add_labels(label)
    @issue.reload

    result = @issue.to_hierarchy_model

    assert_equal label.to_hierarchy_model, result.dig(:labels, 0)
  end

  test "#to_hierarchy_model handles issues with PRs" do
    enable_feature_flag(:tasklist_block, @pull_request.owner)
    result = @pull_request.issue.to_hierarchy_model

    assert_equal "PULL_REQUEST", result[:itemType]
    assert_equal :merged, result[:state]
  end

  test "#to_hierarchy_model returns nil if repository destroyed" do
    @issue.repository.destroy
    @issue.reload

    expected_keys = {
      "Body": "Issue#to_hierarchy_model returned nil due to missing repository",
      "code.namespace": "Issue::IssuesGraphDependency",
      "code.function": "to_hierarchy_model",
      "gh.issue.id": @issue.id,
    }

    assert_logged(**expected_keys) do
      assert_nil @issue.to_hierarchy_model
    end
  end

  class IssueHierarchyModelV2Test < GitHub::TestCase
    fixtures do
      user = create(:user)
      repo = create(:repository, owner: user)
      @issue = create(:issue, repository: repo, title: "issue title", body: "issue body", user: user)
    end
    test "#to_hierarchy_model_key" do

      result = @issue.to_hierarchy_model_key

      assert_equal @issue.repository.owner_id, result[:ownerId]
      assert_equal @issue.id, result[:itemId]
    end

    test "#to_hierarchy_model" do
      result = @issue.to_hierarchy_model

      assert_equal @issue.repository_id, result[:repoId]
      assert_equal @issue.repository.owner_id, result.dig(:key, :ownerId)
      assert_equal @issue.id, result.dig(:key, :itemId)
      assert_equal @issue.title, result[:title]
      assert_equal @issue.url, result[:url]
      assert_equal @issue.state, result[:state]
      assert_nil   result[:stateReason]
      assert_equal @issue.number, result[:number]
      assert_equal @issue.repository.name, result[:repoName]
      assert_equal @issue.repository.owner.login, result[:userName]
    end
  end

  context "#to_omnibar_result" do
    test "returns an issue has a hash" do
      # it's ok to hardcode id here because the issue does not get saved
      issue = build(:issue, id: 1, state: "closed", state_reason: "not_planned")

      expected = {
        id: issue.id,
        title: issue.title,
        url: issue.url,
        type: :issue,
        state: issue.state.to_sym,
        state_reason: issue.state_reason.to_sym,
        number: issue.number,
      }
      assert_same_hash expected, issue.to_omnibar_result
    end

    test "compacts nil values" do
      # it's ok to hardcode id here because the issue does not get saved
      issue = build(:issue, id: 1, state: "open", state_reason: nil)

      expected = {
        id: issue.id,
        title: issue.title,
        url: issue.url,
        type: :issue,
        state: issue.state.to_sym,
        number: issue.number,
      }
      assert_same_hash expected, issue.to_omnibar_result
    end

    test "returns type pull_request when issue has a pull request" do
      pull_request = create(:pull_request, :disable_disk_access)
      issue = pull_request.issue

      expected = {
        id: issue.id,
        title: issue.title,
        url: issue.url,
        type: :pull_request,
        state: issue.state.to_sym,
        number: issue.number,
      }
      assert_same_hash expected, issue.to_omnibar_result
    end

    test "returns :merged as state for a merged pull_request" do
      pull_request = create(:pull_request, :disable_disk_access, :merged)
      issue = pull_request.issue

      assert_equal :merged, issue.to_omnibar_result[:state]
    end

    test "returns :draft as state for a draft pull_request" do
      pull_request = create(:pull_request, :disable_disk_access, reviewable_state: :draft)
      issue = pull_request.issue

      assert_equal :draft, issue.to_omnibar_result[:state]
    end
  end

  context "#to_tasklist_issue" do
    test "builds a TasklistBlocks::Issue from a given issue" do
      result = @issue.to_tasklist_issue
      assert_equal TasklistBlocks::Issue, result.class
    end
  end

  context "#parent_issues" do
    test "returns empty array if there is no hierarchy_state" do
      issue = build(:issue)
      issue.stubs(:hierarchy_state).returns(nil)
      assert_empty issue.parent_issues
    end

    test "returns empty array if there is no trackedBy on hierarchy_state" do
      issue = build(:issue)
      hierarchy_state = Struct.new(:trackedBy).new(nil)
      issue.stubs(:hierarchy_state).returns(hierarchy_state)
      assert_empty issue.parent_issues
    end

    test "returns empty array if there are no tracking blocks in trackedBy on hierarchy_state" do
      issue = build(:issue)
      hierarchy_state = Struct.new(:trackedBy).new([])
      issue.stubs(:hierarchy_state).returns(hierarchy_state)
      assert_empty issue.parent_issues
    end

    test "returns empty array if there are no issues in the tracking blocks in trackedBy on hierarchy_state" do
      issue = build(:issue)
      tracking_block = build_proto_tasklist_block(issues: [])
      hierarchy_state = Struct.new(:trackedBy).new([tracking_block])
      issue.stubs(:hierarchy_state).returns(hierarchy_state)
      assert_empty issue.parent_issues
    end

    test "returns empty array if the only issue in the tracking blocks has an id of zero" do
      issue = build(:issue)
      zero_issue = build_proto_issue(key: build_proto_key(item_id: 0))
      tracking_block = build_proto_tasklist_block(issues: [zero_issue])

      hierarchy_state = Struct.new(:trackedBy).new([tracking_block])
      issue.stubs(:hierarchy_state).returns(hierarchy_state)
      assert_empty issue.parent_issues
    end

    test "returns empty array if the only issue in the tracking blocks has repoId of zero" do
      issue = build(:issue)
      zero_issue = build_proto_issue(key: build_proto_key(item_id: 10), repo_id: 0)
      tracking_block = build_proto_tasklist_block(issues: [zero_issue])

      hierarchy_state = Struct.new(:trackedBy).new([tracking_block])
      issue.stubs(:hierarchy_state).returns(hierarchy_state)
      assert_empty issue.parent_issues
    end

    test "returns an array of TasklistBlocks::Issue objects" do
      issue = build(:issue)
      non_zero_issue = build_proto_issue(key: build_proto_key(item_id: 10), repo_id: 10)
      tracking_block = build_proto_tasklist_block(issues: [non_zero_issue])

      hierarchy_state = Struct.new(:trackedBy).new([tracking_block])
      issue.stubs(:hierarchy_state).returns(hierarchy_state)
      expected = [TasklistBlocks::Issue.from_proto(issue: non_zero_issue)]
      assert_equal expected, issue.parent_issues
    end

    test "returns an deduplicated array of TasklistBlocks::Issue objects" do
      issue = build(:issue)
      non_zero_issue = build_proto_issue(key: build_proto_key(item_id: 10), repo_id: 10)
      tracking_block = build_proto_tasklist_block(issues: [non_zero_issue])

      hierarchy_state = Struct.new(:trackedBy).new([tracking_block, tracking_block]) # dupe here
      issue.stubs(:hierarchy_state).returns(hierarchy_state)
      expected = [TasklistBlocks::Issue.from_proto(issue: non_zero_issue)]
      assert_equal expected, issue.parent_issues
    end
  end
end
