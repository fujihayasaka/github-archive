# typed: true
# frozen_string_literal: true

require "test_helper"

class RefPushTest < GitHub::TestCase
  include BackgroundDeletesTestHelpers

  fixtures do
    @user = create(:user)
    @another_user = create(:user)
    @repo = create(:repository, owner: @user)
    @repo.add_member(@another_user)
  end

  setup do
    example_repo :simple, @repo
  end

  test "is deleted with repository" do
    payload = {
      before: "4c8124ffcf4039d292442eeccabdeca5af5c5017",
      after: "a47fd41f3aa4610ea527dcc1669dfdb9c15c5425",
      pusher: @user,
      pushed_at: Time.now
    }
    other_repo = create(:repository)
    push = Push.create!(payload.merge(repository: @repo, ref: "refs/heads/master1"))
    other_push = Push.create!(payload.merge(repository: other_repo, ref: "refs/heads/master2"))
    assert RefPush.log_push(push)
    assert RefPush.log_push(other_push)
    ref_push = RefPush.find_by!(repository: @repo, ref: "refs/heads/master1")
    other_ref_push = RefPush.find_by!(repository: other_repo, ref: "refs/heads/master2")

    assert_destroyed_in_background_with_parent do |config|
      config.parent_record = @repo
      config.expect_destroyed = [ref_push]
      config.expect_not_destroyed = [other_ref_push]
    end
  end

  context "#log_push" do
    test "handles race conditions in log_push" do
      # Edit happens before delete
      edit = Push.create({
        before: "4c8124ffcf4039d292442eeccabdeca5af5c5017",
        after: "a47fd41f3aa4610ea527dcc1669dfdb9c15c5425",
        ref: "refs/heads/master",
        repository: @repo,
        pusher: @user,
        pushed_at: Time.now
      })
      delete = Push.create({
        before: "a47fd41f3aa4610ea527dcc1669dfdb9c15c5425",
        after: GitHub::NULL_OID,
        ref: "refs/heads/master",
        repository: @repo,
        pusher: @user,
        pushed_at: Time.now + 1.second
      })

      # Ensure no matter the order of these pushes that the outcome is always the same
      [edit, delete].permutation.each do |order|
        order.each do |push|
          RefPush.log_push(push)
        end

        ref_push = RefPush.find_by(repository: @repo, ref: "refs/heads/master", pusher: @user)
        refute ref_push, "should be deleted. event order:#{order.map(&:pushed_at)}"

        RefPush.where(repository: @repo).delete_all
      end
    end

    test "deletes only older edits when deleting" do
      # Actual order: User edits, deletes, and then re-creates
      # Expected result: The only non-deleted entry should be the re-creation
      edit_older = Push.create({
        before: "4c8124ffcf4039d292442eeccabdeca5af5c5017",
        after: "a47fd41f3aa4610ea527dcc1669dfdb9c15c5425",
        ref: "refs/heads/master",
        repository: @repo,
        pusher: @user,
        pushed_at: Time.now
      })
      delete = Push.create({
        before: "a47fd41f3aa4610ea527dcc1669dfdb9c15c5425",
        after: GitHub::NULL_OID,
        ref: "refs/heads/master",
        repository: @repo,
        pusher: @user,
        pushed_at: Time.now + 1.second
      })
      edit_newer = Push.create({
        before: GitHub::NULL_OID,
        after: "a47fd41f3aa4610ea527dcc1669dfdb9c15c5426",
        ref: "refs/heads/master",
        repository: @repo,
        pusher: @user,
        pushed_at: Time.now + 2.seconds
      })

      # Ensure no matter the order of these pushes that the outcome is always the same
      [edit_older, edit_newer, delete].permutation.each do |order|
        order.each do |push|
          RefPush.log_push(push)
        end

        ref_push = RefPush.find_by(repository: @repo, ref: "refs/heads/master", pusher: @user)
        assert ref_push, "should not be deleted. event order:#{order.map(&:pushed_at)}"

        RefPush.where(repository: @repo).delete_all
      end
    end

    test "other user RefPush stays deleted when primary user deletes and recreates" do
      # Actual order: 1 user edits, another user deletes, and then the first user re-creates
      # Expected result: The only non-deleted entry should be the re-creation
      other_user_edit = Push.create({
        before: "4c8124ffcf4039d292442eeccabdeca5af5c5017",
        after: "a47fd41f3aa4610ea527dcc1669dfdb9c15c5425",
        ref: "refs/heads/master",
        repository: @repo,
        pusher: @another_user,
        pushed_at: Time.now
      })
      delete = Push.create({
        before: "a47fd41f3aa4610ea527dcc1669dfdb9c15c5425",
        after: GitHub::NULL_OID,
        ref: "refs/heads/master",
        repository: @repo,
        pusher: @user,
        pushed_at: Time.now + 1.second
      })
      re_create = Push.create({
        before: GitHub::NULL_OID,
        after: "a47fd41f3aa4610ea527dcc1669dfdb9c15c5426",
        ref: "refs/heads/master",
        repository: @repo,
        pusher: @user,
        pushed_at: Time.now + 2.seconds
      })

      # Ensure no matter the order of these pushes that the outcome is always the same
      [other_user_edit, delete, re_create].permutation.each do |order|
        order.each do |push|
          RefPush.log_push(push)
        end

        user_push = RefPush.find_by(repository: @repo, ref: "refs/heads/master", pusher: @user)
        assert user_push, "should not be deleted. event order:#{order.map(&:pushed_at)}"

        other_user_push = RefPush.find_by(repository: @repo, ref: "refs/heads/master", pusher: @another_user)
        refute other_user_push, "should be deleted. event order:#{order.map(&:pushed_at)}"

        RefPush.where(repository: @repo).delete_all
      end
    end
  end if GitHub.flipper[:ref_push_delete].enabled?
end
