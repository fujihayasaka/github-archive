# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectItem::ConvertToIssueTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)
  end

  setup do
    Storage::UserAssetTransfer::DraftToRepositoryTransfer.any_instance.stubs(:handle_s3_objects)
  end

  context "#call" do
    test "can convert draft issue to issue in repository and transfers its assets" do
      content = create(:draft_issue)
      asset = create(:user_asset, uploader: content.memex_project.owner, upload_container: content.memex_project)
      body = draft_body_with_assets(asset)
      content.update(body: body)

      memex_item = build(:memex_project_item, content: content)
      draft_issue_content = memex_item.content
      draft_issue_title = memex_item.content.title

      expected_body = repository_issue_body_with_assets(asset)

      MemexProjectItem::ConvertToIssue.call(memex_project_item: memex_item, actor: content.memex_project.owner, repository: @repo)

      assert_equal Issue, memex_item.content.class
      assert_equal draft_issue_title, memex_item.content.title
      refute_equal draft_issue_content, memex_item.content
      assert_equal expected_body, memex_item.content.body

      asset.reload

      assert_equal @repo.id, asset.repository_id
      assert_equal @repo, asset.upload_container
    end

    test "it doesn't convert draft if actor is not authorized to see assets in the body" do
      content = create(:draft_issue)
      asset = create(:user_asset, uploader: content.memex_project.owner, upload_container: content.memex_project)
      body = draft_body_with_assets(asset)
      content.update(body: body)

      memex_item = build(:memex_project_item, content: content)
      draft_issue_content = memex_item.content
      draft_issue_title = memex_item.content.title

      assert_raises Storage::UserAssetTransfer::Transfer::TransferError do
        MemexProjectItem::ConvertToIssue.call(memex_project_item: memex_item, actor: @user, repository: @repo)
      end

      refute_equal Issue, memex_item.content.class
      assert_equal draft_issue_content, memex_item.content
      assert_equal body, memex_item.content.body

      assert_nil asset.repository
      assert_equal asset.upload_container, content.memex_project
    end

    test "draft issue title is used for issue title" do
      title = "this is a new draft issue title"

      content = create(:draft_issue, title: title)
      memex_item = build(:memex_project_item, content: content)

      MemexProjectItem::ConvertToIssue.call(memex_project_item: memex_item, actor: @user, repository: @repo)

      assert_equal title, memex_item.content.title
    end

    test "draft issue body is used for issue body" do
      body = "issue body is here"

      content = create(:draft_issue, body: body)
      memex_item = build(:memex_project_item, content: content)

      MemexProjectItem::ConvertToIssue.call(memex_project_item: memex_item, actor: @user, repository: @repo)

      assert_equal body, memex_item.content.body
    end

    test "draft issue assignees are used for issue assignees" do
      body = "issue body is here"

      content = create(:draft_issue, body: body, assignees: [@user])
      memex_item = build(:memex_project_item, content: content)

      MemexProjectItem::ConvertToIssue.call(memex_project_item: memex_item, actor: @user, repository: @repo)

      assert_equal body, memex_item.content.body
      assert_equal [@user], memex_item.content.assignees
    end

    test "draft issue invalid assignees are not used for issue assignees" do
      body = "issue body is here"

      private_repo = create(:private_repository, owner: @user)
      some_user = create(:user)

      content = create(:draft_issue, body: body, assignees: [@user, some_user])
      memex_item = build(:memex_project_item, content: content)

      warnings = MemexProjectItem::ConvertToIssue.call(memex_project_item: memex_item, actor: @user,
        repository: private_repo)

      assert_equal body, memex_item.content.body
      assert_equal [@user], memex_item.content.assignees
      assert_equal [some_user.login], warnings.invalid_assignee_logins
    end

    test "new issue created when conversion completed" do
      content = create(:draft_issue)
      old_draft_id = content.id

      memex_item = build(:memex_project_item, content: content)

      MemexProjectItem::ConvertToIssue.call(memex_project_item: memex_item, actor: @user, repository: @repo)

      new_id = memex_item.content.id
      assert Issue.exists?(memex_item.content.id)
    end

    test "destroys existing draft issue when completed" do
      content = create(:draft_issue)
      old_draft_id = content.id

      memex_item = build(:memex_project_item, content: content)

      MemexProjectItem::ConvertToIssue.call(memex_project_item: memex_item, actor: @user, repository: @repo)

      refute DraftIssue.exists?(old_draft_id)
    end

    test "raises error if invoked on issue" do
      content = create(:issue)
      memex_item = build(:memex_project_item, content: content)

      ex = assert_raises MemexProjectItem::ConvertToIssue::Error do
        MemexProjectItem::ConvertToIssue.call(memex_project_item: memex_item, actor: @user, repository: @repo)
      end

      assert_equal "Cannot convert an issue into an issue", ex.message
    end

    test "raises error if invoked on pull request" do
      content = create(:pull_request, :disable_disk_access)
      memex_item = build(:memex_project_item, content: content)

      ex = assert_raises MemexProjectItem::ConvertToIssue::Error do
        MemexProjectItem::ConvertToIssue.call(memex_project_item: memex_item, actor: @user, repository: @repo)
      end

      assert_equal "Cannot convert a pull request into an issue", ex.message
    end

    test "raises error if repository has issues disabled" do
      content = create(:draft_issue)
      memex_item = build(:memex_project_item, content: content)

      repo = create(:private_repository, owner: @user, has_issues: false)

      ex = assert_raises MemexProjectItem::ConvertToIssue::Error do
        MemexProjectItem::ConvertToIssue.call(memex_project_item: memex_item, actor: @user, repository: repo)
      end

      assert_equal "Issues are not enabled for this repository", ex.message
    end

    test "raises error if user does not have access to repository" do
      content = create(:draft_issue)
      memex_item = build(:memex_project_item, content: content)

      another_user = create(:verified_user)
      repo = create(:private_repository, owner: another_user)

      ex = assert_raises MemexProjectItem::ConvertToIssue::Error do
        MemexProjectItem::ConvertToIssue.call(memex_project_item: memex_item, actor: @user, repository: repo)
      end

      assert_equal "User does not have access to this repository", ex.message
    end

    test "re-raises validation errors from the project item" do
      memex = create(:memex_project)
      draft_item = memex.build_draft_issue(creator: @user, title: "To be converted").tap(&:save!)
      draft_item.expects(:update).returns(false)

      assert_raises ActiveRecord::RecordNotSaved do
        MemexProjectItem::ConvertToIssue.call(memex_project_item: draft_item, actor: @user, repository: @repo)
      end
    end

    test "it doesn't transfer issue if something wrong happend while transfering user assets" do
      content = create(:draft_issue)
      asset = create(:user_asset, uploader: content.memex_project.owner, upload_container: content.memex_project)
      body = draft_body_with_assets(asset)
      content.update(body: body)

      memex_item = build(:memex_project_item, content: content)
      draft_issue_content = memex_item.content
      draft_issue_title = memex_item.content.title

      Storage::UserAssetTransfer::DraftToRepositoryTransfer
        .stubs(:transfer_by_urls)
        .raises(Storage::UserAssetTransfer::Transfer::TransferError)

      Issue.expects(:transaction).never

      assert_raises Storage::UserAssetTransfer::Transfer::TransferError do
        MemexProjectItem::ConvertToIssue.call(memex_project_item: memex_item, actor: @user, repository: @repo)
      end
    end

    test "instruments draft issue conversion" do
      user = create(:user)
      content = create(:draft_issue)
      memex_item = create(:memex_project_item, content: content)
      old_draft_id = memex_item.content.id

      expected_payload = {
        actor: user,
        draft_issue: memex_item.content,
        issue: nil,
        project: memex_item.memex_project,
        project_item: memex_item,
        request_context: GitHub.context.to_hash,
      }

      calls = {}
      GlobalInstrumenter.expects(:instrument).at_least_once.with { calls[_1] = _2 }

      MemexProjectItem::ConvertToIssue.call(memex_project_item: memex_item, actor: user, repository: @repo)

      assert_equal(
        expected_payload.merge({ issue: memex_item.content }),
        calls[MemexProjectItem::ConvertToIssue::ON_DRAFT_ISSUE_CONVERT_INSTRUMENTATION_KEY]
      )

      refute DraftIssue.exists?(old_draft_id)
    end

    test "instrumentation payload executes no new queries" do
      user = create(:user)
      content = create(:draft_issue)
      memex_item = create(:memex_project_item, content: content)
      issue = create(:issue)
      converter = MemexProjectItem::ConvertToIssue.new(memex_project_item: memex_item, actor: user, repository: @repo)

      assert_query_count(0) do
        converter.hydro_payload(content, issue)
      end
    end

    test "publishes Hydro message on convert" do
      Timecop.freeze do
        user = create(:user)
        content = create(:draft_issue)
        memex_item = create(:memex_project_item, content: content)

        MemexProjectItem::ConvertToIssue.call(memex_project_item: memex_item, actor: user, repository: @repo)

        expected_payload = {
          actor: Hydro::EntitySerializer.user(user),
          draft_issue: Hydro::EntitySerializer.draft_issue(content),
          project: Hydro::EntitySerializer.memex_project(memex_item.memex_project),
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          issue: Hydro::EntitySerializer.issue(memex_item.content),
          project_item: Hydro::EntitySerializer.memex_project_item(memex_item),
        }

        assert_hydro_published(
          expected_payload,
          schema: "github.memex.v0.DraftIssueConvertToIssue",
        )
      end
    end
  end

  context "#transfer_assets_to_repository" do
    test "it transfers asset to repository" do
      converter, asset = setup_transfer_assets_to_repository

      body = draft_body_with_assets(asset)
      expected_body = repository_issue_body_with_assets(asset)

      res = converter.send(:transfer_assets_to_repository, body)
      assert res.body_changed
      assert_equal expected_body, res.new_body

      asset.reload

      assert_equal @repo.id, asset.repository_id
      assert_equal @repo, asset.upload_container
    end

    test "it doesn't call UserAsset#transfer_by_urls if body doesn't have urls" do
      converter, asset = setup_transfer_assets_to_repository

      body = <<~TEXT
        This is a draft issue:

        Please review and provide feedback.

        Thanks!
      TEXT

      Storage::UserAssetTransfer::Transfer.any_instance.expects(:transfer_by_urls).never

      res = converter.send(:transfer_assets_to_repository, body)
      refute res.body_changed
      assert_equal body, res.new_body
    end

    test "it doesn't translate urls in body if UserAsset#transfer_by_urls doesn't return translations" do
      converter, asset = setup_transfer_assets_to_repository

      body = draft_body_with_assets(asset)

      Storage::UserAssetTransfer::Transfer.any_instance.stubs(:transfer_by_urls).returns([])

      res = converter.send(:transfer_assets_to_repository, body)
      refute res.body_changed
      assert_equal body, res.new_body
    end
  end

  def setup_transfer_assets_to_repository
    content = create(:draft_issue)
    memex_item = build(:memex_project_item, content: content)
    asset = create(:user_asset, uploader: content.memex_project.owner, upload_container: content.memex_project)
    converter = MemexProjectItem::ConvertToIssue.new(memex_project_item: memex_item, actor: content.memex_project.owner, repository: @repo)

    [converter, asset]
  end

  def draft_body_with_assets(asset)
    <<~TEXT
      This is a draft issue with an image:

      <img src="#{create_draft_asset_url(asset)}" />

      Please review and provide feedback.

      <img src="#{create_draft_asset_url(asset)}" />

      <img src="#{create_unrelated_asset_url(asset)}" />

      https://www.example.com/contact-us
    TEXT
  end

  def repository_issue_body_with_assets(asset)
    <<~TEXT
      This is a draft issue with an image:

      <img src="#{create_repo_asset_url(asset)}" />

      Please review and provide feedback.

      <img src="#{create_repo_asset_url(asset)}" />

      <img src="#{create_unrelated_asset_url(asset)}" />

      https://www.example.com/contact-us
    TEXT
  end

  def create_draft_asset_url(asset)
    "https://github.com/orgs/org/projects/1/assets/#{asset.user_id}/#{asset.guid}"
  end

  def create_repo_asset_url(asset)
    "#{@repo.permalink}/assets/#{asset.user_id}/#{asset.guid}"
  end

  def create_unrelated_asset_url(asset)
    "https://user-assets.githubusercontent.com/#{asset.user_id}/#{asset.guid}"
  end
end
