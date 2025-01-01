# typed: true
# frozen_string_literal: true

require "test_helper"

class Push::PushTest < GitHub::TestCase
  fixtures do
    @mojombo = create(:user, login: "mojombo",  plan: "medium")
    @grit = create(:repository, name: "grit-push-test", owner: @mojombo, has_wiki: true, from_example: :mojombo_grit)

  end

  test "pushed_at cannot be null" do
    ref = @grit.refs.find(@grit.default_branch)
    before = ref.target.oid
    commit = ref.append_commit({ message: "test", author: @mojombo }, @mojombo)

    push = Push.new(
      repository_id: @grit.id,
      pusher_id: @mojombo.id,
      ref: "refs/heads/#{@grit.default_branch}",
      after: commit.oid,
      before: before
    )

    refute push.save
    assert_equal 1, push.errors.count
    assert push.errors.of_kind?(:pushed_at, :blank)
    push.pushed_at = Time.current
    assert push.save
  end
end
