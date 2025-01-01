# typed: true
# frozen_string_literal: true

require "test_helper"

class Repositories::PushTest < GitHub::TestCase
  include DogstatsTestHelpers

  PUSH_ATTRS = %w[id repository_id pusher_id before after ref created_at updated_at pushed_at push_type]

  fixtures do
    @push = create :push, ref: "refs/heads/master"
  end

  setup do
    @repositories_push = Repositories::Push.new(
      @push.id,
      @push.repository_id,
      @push.pusher_id,
      @push.before,
      @push.after,
      @push.ref,
      @push.created_at,
      @push.updated_at,
      @push.pushed_at,
      @push.push_type,
    )
  end

  test ".from_record" do
    push = create :push
    repositories_push = Repositories::Push.from_record(push)

    PUSH_ATTRS.each do |name|
      assert_equal push[name], T.must(repositories_push)[name]
    end
  end

  test ".from_records" do
    pushes = create_list :push, 3
    repositories_pushes = Repositories::Push.from_records(pushes)

    pushes.each_with_index do |push, i|
      PUSH_ATTRS.each do |name|
        assert_equal push[name], T.must(repositories_pushes[i])[name], "#{name} mismatch"
      end
    end
  end

  test "exposes push attributes via named methods and []" do
    PUSH_ATTRS.each do |name|
      assert_equal @push.send(name), @repositories_push.send(name)
      assert_equal @push[name], @repositories_push[name]
    end
  end

  test "exposes expected Push defined methods" do
    assert_equal @push.initial_commit?, @repositories_push.initial_commit?
    assert_equal @push.permalink, @repositories_push.permalink
    assert_equal @push.force_push_push_type?, @repositories_push.force_push_push_type?
    assert_equal @push.on_default_branch?, @repositories_push.on_default_branch?
  end

  test "exposes necessary methods for graphql, platform loader, and association" do
    assert_equal "Push", @repositories_push.platform_type_name
    assert_equal "pushes", Repositories::Push.table_name
    assert_equal "Push", Repositories::Push.polymorphic_name
  end

  test "==" do
    assert @repositories_push == @repositories_push
    assert @repositories_push == Repositories::Push.from_records([@push]).first
  end

  test "#spokes_api_fail_fast_enabled" do
    assert @repositories_push.spokes_api_fail_fast_enabled
    @repositories_push.spokes_api_fail_fast_enabled = false

    refute @repositories_push.spokes_api_fail_fast_enabled
  end

  context "#repository" do
    test "returns repository via domain interface" do
      assert_equal Repositories.domain.by_id(@repositories_push.repository_id), @repositories_push.repository
    end

    test "is preloadable" do
      pushes = create_list :push, 3
      repo_pushes = Repositories::Push.from_records(pushes)

      GitHub::PrefillAssociations.prefill_batch_method(repo_pushes, :repository)

      assert_no_queries do
        repo_pushes.each(&:repository)
      end
    end
  end

  context "#pusher" do
    test "returns pusher via domain interface" do
      assert_equal Users.domain.by_id(@repositories_push.pusher_id), @repositories_push.pusher
    end

    test "is preloadable" do
      pushes = create_list :push, 3
      repo_pushes = Repositories::Push.from_records(pushes)

      GitHub::PrefillAssociations.prefill_batch_method(repo_pushes, :pusher)

      assert_no_queries do
        repo_pushes.each(&:pusher)
      end
    end
  end
end
