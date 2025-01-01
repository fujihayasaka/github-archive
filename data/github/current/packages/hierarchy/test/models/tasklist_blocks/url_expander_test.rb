# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/conditional_access/filter_test_helper"

module TasklistBlocks
  class UrlExpanderTest < GitHub::TestCase
    include ConditionalAccess::FilterTestHelper

    fixtures do
      @org = create(:organization)
      @user = create(:user)
      @repository = create(:repository, owner: @org, has_issues: true)
      @issue = create(:issue, user: @user, repository: @repository)
      @issue2 = create(:issue, user: @user, repository: @repository)
    end

    setup do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      GitHub.flipper[:tasklist_block].enable(@org)
    end

    context ".enabled?" do
      test "enabled for repository in feature flag" do
        assert @repository.owner.feature_enabled?(:tasklist_block), "tasklist_block not enabled for owner"
        assert TasklistBlocks::UrlExpander.enabled?(@issue), "TasklistBlockToMarkdownFilter should be enabled"
      end

      test "disabled for invalid subject type" do
        pull_request = build(:pull_request, repository: @repository)

        assert pull_request.repository.owner.feature_enabled?(:tasklist_block), "tasklist_block not enabled for owner"
        refute TasklistBlocks::UrlExpander.enabled?(pull_request), "TasklistBlockToMarkdownFilter should not be enabled without issue"
      end

      test "disabled for repository not in feature flag" do
        GitHub.flipper[:tasklist_block].disable

        refute @user.feature_enabled?(:tasklist_block), "tasklist_block enabled for owner"
        refute TasklistBlocks::UrlExpander.enabled?(@issue), "TasklistBlocks::UrlExpander should not be enabled"
      end

      test "disabled for blank repository" do
        GitHub.flipper[:tasklist_block].disable

        refute TasklistBlocks::UrlExpander.enabled?(nil), "TasklistBlocks::UrlExpander should not be enabled"
      end
    end

    test "transforms tasklist block url to valid markdown" do
      uuid = SecureRandom.uuid
      url = "#{@issue.url}#tasklist-block-#{uuid}"
      body = <<~MD.chomp
      This is my tasklist issue.

      #{url}
      MD
      issue = build(:issue, user: @user, repository: @repository, body: body)

      # Mock issues-graph service response
      primary_key = IssuesGraph::Proto::PrimaryKey.new(uuid: uuid)
      key = IssuesGraph::Proto::Key.new(primaryKey: primary_key)
      tracked_issue_open = IssuesGraph::Proto::Issue.new(
        key: IssuesGraph::Proto::Key.new(
          ownerId: @user.id,
          itemId: issue.id,
          primaryKey: ::IssuesGraph::Proto::PrimaryKey.new(
            uuid: SecureRandom.uuid,
          )
        ),
        userName: @user.display_login,
        repoId: @repository.id,
        repoName: @repository.name,
        number: 1,
        title: "tracked issue",
        url: "http://dummy-url.github.com/#{@repository.name_with_display_owner}/issues/1",
        state: "open",
      )
      tracked_issue_closed = IssuesGraph::Proto::Issue.new(
        key: IssuesGraph::Proto::Key.new(
          ownerId: @user.id,
          itemId: @issue2.id,
          primaryKey: ::IssuesGraph::Proto::PrimaryKey.new(
            uuid: SecureRandom.uuid,
          )
        ),
        userName: @user.display_login,
        repoId: @repository.id,
        repoName: @repository.name,
        number: 2,
        title: "tracked issue 2",
        url: "http://dummy-url.github.com/#{@repository.name_with_display_owner}/issues/2",
        state: "closed",
      )
      tracked_issue_draft = IssuesGraph::Proto::Issue.new(
        key: IssuesGraph::Proto::Key.new(
          ownerId: @user.id,
          primaryKey: ::IssuesGraph::Proto::PrimaryKey.new(
            uuid: SecureRandom.uuid,
          )
        ),
        userName: @user.display_login,
        title: "Draft issue",
        state: "draft",
      )

      tasklist_block = IssuesGraph::Proto::TrackingBlock.new(key: key, name: "Tracking", issues: [tracked_issue_open, tracked_issue_closed, tracked_issue_draft])
      tasklist_block_response = IssuesGraph::Proto::GetIssueResponse.new(tracking: [tasklist_block])

      issue.stubs(:hierarchy_state).returns(tasklist_block_response)
      issue.stubs(:reconcile_tracking_blocks_after_save)
      issue.save!

      result = TasklistBlocks::UrlExpander.expand(issue)

      expected_markdown = <<~MD
      This is my tasklist issue.

      ```[tasklist]
      ### Tracking
      - [ ] http://dummy-url.github.com/#{@repository.name_with_display_owner}/issues/1
      - [x] http://dummy-url.github.com/#{@repository.name_with_display_owner}/issues/2
      - [ ] Draft issue
      ```
      MD

      assert_equal expected_markdown, result
    end

    test "preserves URL if no tasklist block response available" do
      uuid = SecureRandom.uuid
      url = "#{@issue.url}#tasklist-block-#{uuid}"
      body = <<~MD.chomp
      This is my tasklist issue.

      #{url}
      MD

      issue = build(:issue, user: @user, repository: @repository, body: body)
      issue.stubs(:sync_hierarchy_state).returns(
        ::IssuesGraph::Result.new(data: ::IssuesGraph::Proto::GetIssueResponse.new)
      )
      issue.save!
      result = TasklistBlocks::UrlExpander.expand(issue)

      assert_equal body, result
    end

    test "records unfurl success metric" do
      uuid = SecureRandom.uuid
      url = "#{@issue.url}#tasklist-block-#{uuid}"
      body = <<~MD.chomp
      This is my tasklist issue.

      #{url}
      MD
      issue = build(:issue, user: @user, repository: @repository, body: body)

      # Mock issues-graph service response
      primary_key = IssuesGraph::Proto::PrimaryKey.new(uuid: uuid)
      key = IssuesGraph::Proto::Key.new(primaryKey: primary_key)
      tracked_issue_open = IssuesGraph::Proto::Issue.new(
        key: IssuesGraph::Proto::Key.new(
          ownerId: @user.id,
          itemId: issue.id,
          primaryKey: ::IssuesGraph::Proto::PrimaryKey.new(
            uuid: SecureRandom.uuid,
          )
        ),
        userName: @user.display_login,
        repoId: @repository.id,
        repoName: @repository.name,
        number: 1,
        title: "tracked issue",
        url: "http://dummy-url.github.com/#{@user.display_login}/#{@repository.name}/issues/1",
        state: "open",
      )
      tracked_issue_closed = IssuesGraph::Proto::Issue.new(
        key: IssuesGraph::Proto::Key.new(
          ownerId: @user.id,
          itemId: @issue2.id,
          primaryKey: ::IssuesGraph::Proto::PrimaryKey.new(
            uuid: SecureRandom.uuid,
          )
        ),
        userName: @user.display_login,
        repoId: @repository.id,
        repoName: @repository.name,
        number: 2,
        title: "tracked issue 2",
        url: "http://dummy-url.github.com/#{@user.display_login}/#{@repository.name}/issues/2",
        state: "closed",
      )
      tracked_issue_draft = IssuesGraph::Proto::Issue.new(
        key: IssuesGraph::Proto::Key.new(
          ownerId: @user.id,
          primaryKey: ::IssuesGraph::Proto::PrimaryKey.new(
            uuid: SecureRandom.uuid,
          )
        ),
        userName: @user.display_login,
        title: "Draft issue",
        state: "draft",
      )

      tasklist_block = IssuesGraph::Proto::TrackingBlock.new(
        key: key,
        name: "Tracking",
        issues: [tracked_issue_open, tracked_issue_closed, tracked_issue_draft]
      )
      tasklist_block_response = IssuesGraph::Proto::GetIssueResponse.new(tracking: [tasklist_block])

      issue.stubs(:hierarchy_state).returns(tasklist_block_response)
      issue.stubs(:reconcile_tracking_blocks_after_save)
      issue.save!

      assert_difference 'GitHub.dogstats.increments("issues.tasklists.edit.unfurl", tags: ["result:success"]).count' do
        result = TasklistBlocks::UrlExpander.expand(issue)

        expected_markdown = <<~MD
        This is my tasklist issue.

        ```[tasklist]
        ### Tracking
        - [ ] http://dummy-url.github.com/#{@user.display_login}/#{@repository.name}/issues/1
        - [x] http://dummy-url.github.com/#{@user.display_login}/#{@repository.name}/issues/2
        - [ ] Draft issue
        ```
        MD

        assert_equal expected_markdown, result
      end
    end

    test "records missing metric if missing tasklist block in response" do
      uuid = SecureRandom.uuid
      url = "#{@issue.url}#tasklist-block-#{uuid}"
      body = <<~MD.chomp
      This is my tasklist issue.

      #{url}
      MD
      issue = build(:issue, user: @user, repository: @repository, body: body)
      issue.stubs(:sync_hierarchy_state).returns(
        ::IssuesGraph::Result.new(data: ::IssuesGraph::Proto::GetIssueResponse.new)
      )
      issue.save!

      assert_difference 'GitHub.dogstats.increments("issues.tasklists.edit.unfurl.missing").count' do
        TasklistBlocks::UrlExpander.expand(issue)
      end
    end

    test "does not introduce HTML encoding" do
      body = <<~MD.chomp
      <details>
      <summary>This is an issue with non-tasklist content.</summary>
      <p>More details here</p>
      </details>

      ```mermaid
      flowchart TB;
          A[[Hello]]
          B(Bye)
          A --> B;
      ```
      MD
      issue = create(:issue, user: @user, repository: @repository, body: body)
      result = TasklistBlocks::UrlExpander.expand(issue)

      assert_equal body, result
    end

    test "does not affect tasklist block with markdown at rest" do
      body = <<~MD.chomp
      This is my tasklist issue.

      ```[tasklist]
      - [ ] http://dummy-url.github.com/#{@user.display_login}/#{@repository.name}/issues/1
      - [x] http://dummy-url.github.com/#{@user.display_login}/#{@repository.name}/issues/2
      - [ ] Draft issue
      ```
      MD

      issue = build(:issue, user: @user, repository: @repository, body: body)

      result = TasklistBlocks::UrlExpander.expand(issue)

      assert_equal body, result
    end

  end
end
