# typed: true
# frozen_string_literal: true

require "test_helper"

class MoveWorkTest < GitHub::TestCase
  test "user must be present" do
    move_work = build(:move_work, user: nil)

    refute move_work.valid?
    assert_equal "can't be blank", move_work.errors[:user].first
  end

  test "target must be present" do
    move_work = build(:move_work, target: nil)

    refute move_work.valid?
    assert_equal "can't be blank", move_work.errors[:target].first
  end

  test "only allow organizations to be set as target" do
    organization = create(:organization)
    move_work = build(:move_work, user: organization.admin, target: organization)

    assert move_work.valid?

    assert_raises ActiveRecord::AssociationTypeMismatch do
      user = create(:user)
      move_work = build(:move_work, target: user)
    end
  end

  test "sets initial state by default" do
    move_work = build(:move_work, state: nil)

    assert move_work.valid?
    assert move_work.created?
  end

  test "target organization must be adminable by user" do
    user = create(:user)
    org = create(:organization)
    org.add_member(user)
    move_work = build(:move_work, user: user, target: org)

    refute move_work.valid?
    assert_equal "must be adminable by user", move_work.errors[:target].first
  end

  context "start!" do
    test "transition the state to started" do
      move_work = create(:move_work)

      move_work.start!

      assert move_work.started?
    end
  end

  context "complete!" do
    test "transition the state to completed" do
      move_work = create(:move_work, :started)

      move_work.complete!

      assert move_work.completed?
    end
  end

  context ".started_for?" do
    test "returns true if there is a started move work for the giving resource" do
      owner = create(:user)
      org = create(:organization, admin: owner)
      repository = create(:repository, owner: owner)
      move_work = create(:move_work, :started, user: owner, origin: owner, target: org)
      create(:move_work_item, resource: repository, move_work: move_work)

      assert MoveWork.started_for?(owner, repository)
    end

    test "returns false if there isn't a started move work for the giving resource" do
      owner = create(:user)
      org = create(:organization, admin: owner)
      repository = create(:repository, owner: owner)
      move_work = create(:move_work, :completed, user: owner, origin: owner, target: org)
      create(:move_work_item, resource: repository, move_work: move_work)

      refute MoveWork.started_for?(owner, repository)
    end
  end
end
