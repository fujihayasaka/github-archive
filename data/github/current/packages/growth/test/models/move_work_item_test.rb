# typed: true
# frozen_string_literal: true

require "test_helper"

class MoveWorkItemTest < GitHub::TestCase
  test "move work must be present" do
    item = build(:move_work_item, move_work: nil)

    refute item.valid?
    assert_equal "can't be blank", item.errors[:move_work].first
  end

  test "resource must be present" do
    item = build(:move_work_item, resource: nil)

    refute item.valid?
    assert_equal "is not included in the list", item.errors[:resource_type].first
  end

  test "resource must be from a valid type" do
    item = build(:move_work_item, :with_repository)

    assert item.valid?

    item = build(:move_work_item, :with_project)

    assert item.valid?

    item = build(:move_work_item, :with_memex_project)

    assert item.valid?

    user = create(:user)
    item = build(:move_work_item, resource: user)

    refute item.valid?
    assert_equal "is not included in the list", item.errors[:resource_type].first
  end

  test "repository must be adminable by user" do
    user = create(:user)
    org = create(:organization, admin: user)
    user_repo = create(:repository, owner: user)

    move_work = create(:move_work, user: user, target: org)
    item = build(:move_work_item, move_work: move_work, resource: user_repo)

    assert item.valid?

    user_member_repo = create(:repository)
    user_member_repo.add_member(user)
    item = build(:move_work_item, move_work: move_work, resource: user_member_repo)

    refute item.valid?
    assert_equal "is not adminable by user", item.errors[:resource].first
  end

  test "project must be adminable by user" do
    user = create(:user)
    org = create(:organization, admin: user)
    user_project = create(:project, owner: user)

    move_work = create(:move_work, user: user, target: org)
    item = build(:move_work_item, move_work: move_work, resource: user_project)

    assert item.valid?

    user_member_project = create(:project)
    user_member_project.update_user_permission(user, :read)
    item = build(:move_work_item, move_work: move_work, resource: user_member_project)

    refute item.valid?
    assert_equal "is not adminable by user", item.errors[:resource].first
  end
end
