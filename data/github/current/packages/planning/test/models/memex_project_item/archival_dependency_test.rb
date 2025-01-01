# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectItem::ArchivalDependencyTest < GitHub::TestCase
  fixtures do
    @memex = create(:memex_project)
    @user = create(:user)
    @issue = create(:issue)
    @draft_issue = create(:draft_issue)
  end

  context "validations" do
    test "rejects a memex item from being archived when the memex project hits the archive limit" do
      unarchived_item = create(:memex_project_item, memex_project: @memex)
      refute_predicate unarchived_item, :archived?

      archived_item = create(:memex_project_item, memex_project: @memex, archived_at: Time.zone.now, archiver: @user)
      assert_predicate archived_item, :archived?

      fake_limit = @memex.memex_project_items.archived.count

      @memex.stubs(:archived_items_limit).returns(fake_limit)
      unarchived_item.archived_at = Time.zone.now
      assert_not unarchived_item.save
      assert unarchived_item.errors.added?(:base, :archive_limit_reached, limit: fake_limit)

      assert @memex.memex_project_items.count > fake_limit
    end

    test "archive limit reached error message includes archived item limit" do
      unarchived_item = create(:memex_project_item, memex_project: @memex)
      refute_predicate unarchived_item, :archived?

      archived_item = create(:memex_project_item, memex_project: @memex, archived_at: Time.zone.now, archiver: @user)
      assert_predicate archived_item, :archived?

      fake_limit = @memex.memex_project_items.archived.count

      @memex.stubs(:archived_items_limit).returns(fake_limit)
      unarchived_item.archived_at = Time.zone.now
      assert_not unarchived_item.save
      assert_includes unarchived_item.errors.messages_for(:base),
        "Cannot archive more than #{fake_limit} items. To archive more items, please delete existing archived items."
    end

    test "does not include archived content when enforcing memex item limit" do
      # allow at most another item from current count
      fake_limit = @memex.memex_project_items.count + 1

      archived_item = create(:memex_project_item, memex_project: @memex, archived_at: Time.zone.now, archiver: @user)
      assert_predicate archived_item, :archived?

      MemexProjectItem.stub_const(:PER_PAGE_LIMIT, fake_limit) do
        assert @memex.memex_project_items.count == fake_limit

        item = build(:memex_project_item, memex_project: @memex, content: create(:issue))
        assert item.save

        assert @memex.memex_project_items.count > fake_limit
      end
    end
  end

  context "archive!" do
    test "sets fields on model when content is issue" do
      memex_item = build(:memex_project_item, content: @issue)

      memex_item.archive!

      refute_nil memex_item.archived_at
      refute_nil memex_item.archiver
    end

    test "sets fields on model when content is pull request" do
      content = create(:pull_request, :disable_disk_access)
      memex_item = build(:memex_project_item, content: content)

      memex_item.archive!

      refute_nil memex_item.archived_at
      refute_nil memex_item.archiver
    end

    # updated as of https://github.com/github/memex/issues/4791
    # users can now archive a draft issue
    test "sets fields when content is draft issue" do
      memex_item = build(:memex_project_item, content: @draft_issue)

      memex_item.archive!

      refute_nil memex_item.archived_at
      refute_nil memex_item.archiver
    end

    test "does not change archived_at if already archived" do
      earlier = Date.new(2021, 1, 1, 1)
      memex_item = build(:memex_project_item, content: @issue, archived_at: earlier)

      memex_item.archive!

      assert_equal earlier, memex_item.archived_at
    end

    test "requires archiver if archived_at is set on create or update" do
      memex_item = build(:memex_project_item, content: @issue, archived_at: DateTime.now)

      refute memex_item.save
      assert_includes memex_item.errors.full_messages, "Archiver must be set if archived_at is set"

      memex_item.update(archiver: @user)
      assert memex_item.save

      memex_item.update(archiver: nil)
      refute memex_item.save
      assert_includes memex_item.errors.full_messages, "Archiver must be set if archived_at is set"
    end

    test "requires archived_at if archiver is set on create or update" do
      memex_item = build(:memex_project_item, content: @issue, archiver: @user)

      refute memex_item.save
      assert_includes memex_item.errors.full_messages, "Archived at must be set if archiver is set"

      memex_item.update(archived_at: DateTime.now)
      assert memex_item.save

      memex_item.update(archived_at: nil)
      refute memex_item.save
      assert_includes memex_item.errors.full_messages, "Archived at must be set if archiver is set"
    end

    test "does not require archiver for updates if already existed as archived without archiver" do
      memex_item = build(:memex_project_item, content: @issue, priority: 1, archived_at: DateTime.now)

      # skip validation to allow creating an archived item without archiver, as older existing archived items are
      assert memex_item.save(validate: false)
      refute_nil memex_item.archived_at
      assert_nil memex_item.archiver

      # update anything besides archived_at or archiver with no problem
      memex_item.update(priority: 2)
      assert memex_item.save
      refute_nil memex_item.archived_at
      assert_nil memex_item.archiver

      # unarchive with no problem
      memex_item.update(archived_at: nil)
      assert memex_item.save
      assert_nil memex_item.archived_at
      assert_nil memex_item.archiver
    end
  end

  context "unarchive!" do
    test "nullifies fields on model when content is issue" do
      memex_item = build(:memex_project_item, content: @issue)
      memex_item.archive!

      refute_nil memex_item.archived_at
      refute_nil memex_item.archiver

      memex_item.unarchive!

      assert_nil memex_item.archived_at
      assert_nil memex_item.archiver
    end

    test "nullifies fields on model when content is pull request" do
      content = create(:pull_request, :disable_disk_access)
      memex_item = build(:memex_project_item, content: content)
      memex_item.archive!

      refute_nil memex_item.archived_at
      refute_nil memex_item.archiver

      memex_item.unarchive!

      assert_nil memex_item.archived_at
      assert_nil memex_item.archiver
    end

    # updated as of https://github.com/github/memex/issues/4791
    # users can now archive a draft issue
    test "nullifies fields when content is draft issue" do
      memex_item = build(:memex_project_item, content: @draft_issue)
      memex_item.archive!

      refute_nil memex_item.archived_at
      refute_nil memex_item.archiver

      memex_item.unarchive!

      assert_nil memex_item.archived_at
      assert_nil memex_item.archiver
    end

    test "does not update if the item is not in an archived state" do
      memex_item = build(:memex_project_item, content: @issue)

      assert_nil memex_item.archived_at
      assert_nil memex_item.archiver

      memex_item.unarchive!

      memex_item.expects(:update!).never
    end
  end
end
