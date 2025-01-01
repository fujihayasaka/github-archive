# typed: true
# frozen_string_literal: true

require "test_helper"

class Repositories::Domain::PushesTest < GitHub::TestCase

  fixtures do
    @user = create :user
    @another_user = create :user
    @repo = create :repository, name: "smile"

    @user_push1 = create :push, repository: @repo, pusher: @user, ref: "refs/heads/master", created_at: 2.minutes.ago, pushed_at: 2.minutes.ago
    @user_push2 = create :push, repository: @repo, pusher: @user, ref: "refs/heads/master", created_at: 300.days.ago, pushed_at: 300.days.ago

    @user_push3 = create :push, repository: @repo, pusher: @user, ref: "refs/heads/feature", created_at: 1.hour.ago, pushed_at: 1.hour.ago, after: "9d4fd8fac2e227e78b79aeac35abb1aed5660d0c"

    @user_push4 = create :push, repository: @repo, pusher: @user, ref: "refs/heads/feature", created_at: 301.days.ago, pushed_at: 301.days.ago

    @another_user_push1 = create :push, repository: @repo, pusher: @another_user, ref: "refs/heads/master", created_at: 1.minute.ago, pushed_at: 1.minute.ago
  end

  setup do
    @domain = T.must(T.let(Repositories::Domain::Pushes.new(:test), T.nilable(Repositories::Domain::Pushes)))
  end

  sig { returns(Repositories::Domain::Pushes) }
  def domain
    @domain
  end

  context ".latest_for" do
    test "returns recent pushes for repo and user" do
      assert_equal [@user_push1, @user_push3], domain.latest_for(repository: @repo, pusher: @user, pushed_at: 1.day.ago).to_a
      assert_equal [@another_user_push1], domain.latest_for(repository: @repo, pusher: @another_user, pushed_at: 1.day.ago).to_a
    end

    test "returns older pushes for repo and user sorted by date" do
      assert_equal [@user_push1, @user_push3, @user_push2, @user_push4], domain.latest_for(repository: @repo, pusher: @user, pushed_at: 400.days.ago).to_a
    end
  end

  context ".exists_for_ref" do
    test "returns true for recent pushes for repo and ref and user" do
      assert domain.exists_for_ref(repository_id: @repo.id, ref: "master", pusher: @user, pushed_at: 1.day.ago)
      assert domain.exists_for_ref(repository_id: @repo.id, ref: "feature", pusher: @user, pushed_at: 1.day.ago)
      assert domain.exists_for_ref(repository_id: @repo.id, ref: "master", pusher: @another_user, pushed_at: 1.day.ago)
    end

    test "returns true for older pushes for repo and ref and user" do
      assert domain.exists_for_ref(repository_id: @repo.id, ref: "master", pusher: @user, pushed_at: 400.days.ago)
      assert domain.exists_for_ref(repository_id: @repo.id, ref: "feature", pusher: @user, pushed_at: 400.days.ago)
      assert domain.exists_for_ref(repository_id: @repo.id, ref: "master", pusher: @another_user, pushed_at: 400.days.ago)
    end

    test "returns false for pushed_at now and pushers that haven't pushed" do
      refute domain.exists_for_ref(repository_id: @repo.id, ref: "master", pusher: @user, pushed_at: 1.minute.ago)
      refute domain.exists_for_ref(repository_id: @repo.id, ref: "feature", pusher: @user, pushed_at: 1.minute.ago)
      refute domain.exists_for_ref(repository_id: @repo.id, ref: "master", pusher: @another_user, pushed_at: 1.minute.ago)
      refute domain.exists_for_ref(repository_id: @repo.id, ref: "main", pusher: @another_user, pushed_at: 400.days.ago)
      refute domain.exists_for_ref(repository_id: @repo.id, ref: "feature", pusher: @another_user, pushed_at: 400.days.ago)
    end
  end

  context ".latest" do
    test "returns recent pushes for repo newer than specified pushed_at date " do
      assert_equal [@another_user_push1, @user_push1, @user_push3], domain.latest(repository: @repo, pushed_at: 1.day.ago).to_a
      assert_equal [@another_user_push1], domain.latest(repository: @repo, pushed_at: 1.day.ago, limit: 1).to_a
    end

    test "returns older pushes for repo" do
      assert_equal [@another_user_push1, @user_push1, @user_push3, @user_push2, @user_push4], domain.latest(repository: @repo, pushed_at: 400.days.ago).to_a
      assert_equal [@another_user_push1, @user_push1, @user_push3, @user_push2], domain.latest(repository: @repo, pushed_at: 400.days.ago, limit: 4).to_a
    end

    test "returns no pushes when pushed_at is too soon" do
      assert_empty domain.latest(repository: @repo, pushed_at: 1.second.ago)
    end
  end

  context "latest_for_repo" do

    test "returns most recent push for repo" do
      assert_equal @another_user_push1, domain.latest_for_repo(repository_id: @repo.id)
    end

    test "returns nil when no push is returned" do
      empty_repo = create :repository, name: "empty"
      assert_nil domain.latest_for_repo(repository_id: empty_repo.id)
    end
  end

  context "load_pushes_for_repository" do
    test "returns pushes in descending id order" do
      # This function sorts by id descending
      assert_equal [@user_push1], domain.load_pushes_for_repository(push_ids: [@user_push1.id], repository: @repo).to_a
      assert_equal [@another_user_push1, @user_push3, @user_push1], domain.load_pushes_for_repository(push_ids: [@user_push3.id, @another_user_push1.id, @user_push1.id], repository: @repo).to_a
      assert_equal [@another_user_push1, @user_push4, @user_push2, @user_push1], domain.load_pushes_for_repository(push_ids: [@user_push1.id, @another_user_push1.id, @user_push2.id, @user_push4], repository: @repo).to_a
    end

    test "returns no pushes no id matches" do
      assert_empty domain.load_pushes_for_repository(push_ids: [-1, -2, -3], repository: @repo)
    end
  end

  context "by_repository_id" do
    test "returns pushes" do
      assert_equal [@user_push1], domain.by_repository_id(push_ids: [@user_push1.id], repository_id: @repo.id).to_a
      assert_same_elements [@another_user_push1, @user_push3, @user_push1].pluck(:id).sort, domain.by_repository_id(push_ids: [@user_push3.id, @another_user_push1.id, @user_push1.id], repository_id: @repo.id).pluck(:id).to_a
      assert_same_elements [@another_user_push1, @user_push4, @user_push2, @user_push1].pluck(:id).sort, domain.by_repository_id(push_ids: [@user_push1.id, @another_user_push1.id, @user_push2.id, @user_push4], repository_id: @repo.id).pluck(:id).to_a
    end

    test "returns no pushes no id matches" do
      assert_empty domain.by_repository_id(push_ids: [-1, -2, -3], repository_id: @repo.id)
    end
  end

  context "refset_updated_at" do
    test "returns latest refset update for created branch" do
      repo = create :repository
      push = create :push, repository: repo, created_at: 300.days.ago, pushed_at: 300.days.ago, push_type: :branch_creation
      assert_equal push.pushed_at, domain.refset_updated_at(repository_id: repo.id, limit_execution_ms: 2000)
    end

    test "returns latest refset update for deleted branch" do
      repo = create :repository
      push = create :push, repository: repo, created_at: 300.days.ago, pushed_at: 300.days.ago, push_type: :branch_deletion
      assert_equal push.pushed_at, domain.refset_updated_at(repository_id: repo.id, limit_execution_ms: 2000)
    end

    test "returns nil when no refset update" do
      repo = create :repository
      push = create :push, repository: repo, created_at: 300.days.ago, pushed_at: 300.days.ago
      assert_nil domain.refset_updated_at(repository_id: repo.id, limit_execution_ms: 2000)
    end
  end

  context "pushers_for" do
    test "returns all pushers for repo in alphabetical order by login" do
      login_sorted_users = [@user, @another_user].sort_by { |user| user.login }
      assert_equal login_sorted_users, domain.pushers_for(repository: @repo).to_a
    end

    test "returns all pushers for repo and ref in alphabetical order by login" do
      assert_equal [@user], domain.pushers_for(repository: @repo, ref: "refs/heads/feature").to_a
    end

    test "returns no pushers for repo and ref after specified pushed_at" do
      assert_empty domain.pushers_for(repository: @repo, ref: "refs/heads/feature", pushed_at: 5.minutes.ago)
    end
  end

  context "pusher_ids_for_ref" do
    test "returns recent pushers for repo and branch" do
      # As long as we don't care about sort order, we can use assert_same_elements to prevent flakiness.
      # Once we add sorting, we can use assert_equal.
      assert_same_elements [@user.id, @another_user.id], domain.pusher_ids_for_ref(repository: @repo, ref: "master", pushed_at: 1.day.ago)
      assert_equal [@user.id], domain.pusher_ids_for_ref(repository: @repo, ref: "feature", pushed_at: 1.day.ago).to_a
    end

    test "returns older pushers for repo and branch" do
      # As long as we don't care about sort order, we can use assert_same_elements to prevent flakiness.
      # Once we add sorting, we can use assert_equal.
      assert_same_elements [@user.id, @another_user.id], domain.pusher_ids_for_ref(repository: @repo, ref: "master", pushed_at: 400.days.ago)
      assert_equal [@user.id], domain.pusher_ids_for_ref(repository: @repo, ref: "feature", pushed_at: 400.days.ago).to_a
    end

    test "returns no pushers with too recent of a pushed_at for repo and branch" do
      assert_empty domain.pusher_ids_for_ref(repository: @repo, ref: "master", pushed_at: 30.seconds.ago)
      assert_empty domain.pusher_ids_for_ref(repository: @repo, ref: "feature", pushed_at: 30.seconds.ago)
    end
  end

  context "get_by_id_and_repo_id" do
    test "returns push matching provided push id & repo_id" do
      assert_equal @user_push3, domain.by_id_and_repo_id(repository_id: @repo.id, id: @user_push3.id)
    end

    test "returns nil when push not found" do
      another_push = create :push, repository: @repo, pusher: @user, ref: "refs/heads/feature"
      assert_equal another_push, domain.by_id_and_repo_id(repository_id: @repo.id, id: another_push.id)
      another_push.destroy
      assert_nil domain.by_id_and_repo_id(repository_id: @repo.id, id: another_push.id)
    end
  end

  context "by_repo_id_and_after" do
    test "returns push matching provided repo_id & after" do
      assert_equal @user_push3, domain.by_repo_id_and_after(repository_id: @repo.id, after: "9d4fd8fac2e227e78b79aeac35abb1aed5660d0c")
    end

    test "returns push with optional params" do
      another_push = create :push, repository: @repo, pusher: @user, ref: "refs/heads/main", created_at: 1.hour.ago, pushed_at: 1.hour.ago, after: "9d4fd8fac2e227e78b79aeac35abb1aed5660d0c"

      assert_equal another_push, domain.by_repo_id_and_after(repository_id: @repo.id, after: "9d4fd8fac2e227e78b79aeac35abb1aed5660d0c", ref: "refs/heads/main")
    end

    test "returns nil when push not found" do
      assert_nil domain.by_repo_id_and_after(repository_id: @repo.id, after: "9d4fd8fac2e227e78b79aeac35abb1aed5660d0nope")
    end
  end

  context "latest_by_after_and_ref" do
    test "returns push matching provided repo_id, after & ref" do
      another_push = create :push, repository: @repo, pusher: @user, ref: "refs/heads/main", after: "9d4fd8fac2e227e78b79aeac35abb1aed5660d0c", created_at: 1.hour.ago, pushed_at: 1.hour.ago

      assert_equal another_push, domain.latest_by_after_and_ref(repository_id: @repo.id, after: "9d4fd8fac2e227e78b79aeac35abb1aed5660d0c", ref: "refs/heads/main")
    end

    test "returns latest push with required params" do
      another_push = create :push, repository: @repo, pusher: @user, ref: "refs/heads/main", after: "9d4fd8fac2e227e78b79aeac35abb1aed5660d0c", created_at: 1.hour.ago, pushed_at: 1.hour.ago

      assert_equal another_push, domain.latest_by_after_and_ref(repository_id: @repo.id, ref: "refs/heads/main")
    end

    test "returns latest push for multiple refs" do
      create :push, repository: @repo, pusher: @user, ref: "refs/heads/main", after: "9d4fd8fac2e227e78b79aeac35abb1aed5660d0c", created_at: 2.hours.ago, pushed_at: 2.hours.ago

      assert_equal  @user_push3, domain.latest_by_after_and_ref(repository_id: @repo.id, ref: ["refs/heads/main", "refs/heads/feature"])
    end

    test "returns nil when push not found" do
      assert_nil domain.latest_by_after_and_ref(repository_id: @repo.id, after: "9d4fd8fac2e227e78b79aeac35abb1aed5660d0nope", ref: "refs/heads/feature")
    end
  end

  context "by_repository_id_and_refs" do
    test "returns pushes matching provided repo_id & refs sorted by pushed_at" do
      assert_equal [@another_user_push1, @user_push1, @user_push3, @user_push2, @user_push4], domain.by_repository_id_and_refs(repository_id: @repo.id,  refs: ["refs/heads/master", "refs/heads/feature"]).to_a
    end

    test "returns pushes sorted by pushed_at with optional limits" do
      assert_equal [@another_user_push1, @user_push1, @user_push3, @user_push2], domain.by_repository_id_and_refs(repository_id: @repo.id, refs: ["refs/heads/master", "refs/heads/feature"], limit: 4).to_a
    end

    test "returns pushes sorted by pushed_at offset by x" do
      assert_equal [@user_push4], domain.by_repository_id_and_refs(repository_id: @repo.id,  refs: ["refs/heads/master", "refs/heads/feature"], offset: 4).to_a
    end
  end

  context "by_user" do
    test "returns a collection with matching repository_id, pusher_id, excluding ref" do
      result = domain.by_user(repository_id: @repo.id, pusher_id: @user.id, exclude_ref: "refs/heads/master", pagination: GH::Pagination::Cursor.new(first: 5))

      assert_equal result.to_a, [@user_push3, @user_push4]
      refute_includes result.to_a, [@user_push1, @user_push2]
    end

    test "not return branch deletions" do
      deletion_push = create :push, repository: @repo, pusher: @user, ref: "refs/heads/master", push_type: :branch_deletion, created_at: 1.hour.ago, pushed_at: 1.hour.ago

      result = domain.by_user(repository_id: @repo.id, pusher_id: @user.id, exclude_ref: "refs/heads/master", pagination: GH::Pagination::Cursor.new(first: 5))
      refute_includes result.to_a, deletion_push
    end

    test "returns pushes ordered by pushed_at DESC" do
      result = domain.by_user(repository_id: @repo.id, pusher_id: @user.id, exclude_ref: "refs/heads/feature", pagination: GH::Pagination::Cursor.new(first: 5))
      assert_equal result.to_a, [@user_push1, @user_push2]
    end

    test "paginates" do
      result = domain.by_user(repository_id: @repo.id, pusher_id: @user.id, exclude_ref: "refs/heads/master", pagination: GH::Pagination::Cursor.new(first: 1))
      assert_equal [@user_push3], result.to_a
      result = domain.by_user(repository_id: @repo.id, pusher_id: @user.id, exclude_ref: "refs/heads/master", pagination: GH::Pagination::Cursor.new(first: 1, after: result.end_cursor))
      assert_equal [@user_push4], result.to_a
    end
  end

  context "first_before_sha_for" do
    test "finds correct sha for unique after" do
      assert_equal @user_push1.before, domain.first_before_sha_for(repository_id: @repo.id, ref: "refs/heads/master", pusher_id: @user.id, after: @user_push1.after)
    end

    test "returns nil when push does not exist" do
      user = create :user
      repo = create :repository

      create(:push,
        after:      "9d4fd8fac2e227e78b79aeac35abb1aed5660d0b",
        before:     "9d4fd8fac2e227e78b79aeac35abb1aed5660d0a",
        ref:        "refs/heads/master",
        repository_id: repo.id,
        pusher_id: user.id,
        pushed_at: Time.now
      )

      assert_nil domain.first_before_sha_for(repository_id: repo.id, ref: "refs/heads/master", pusher_id: user.id, after: "9d4fd8fac2e227e78b79aeac35abb1aed5660d0c")
    end

    test "finds first before sha for multiple matching after" do
      user = create :user
      repo = create :repository

      create(:push,
        after:      "9d4fd8fac2e227e78b79aeac35abb1aed5660d0a",
        before:     "9d4fd8fac2e227e78b79aeac35abb1aed5660d0b",
        ref:        "refs/heads/master",
        repository_id: repo.id,
        pusher_id: user.id,
        pushed_at: Time.now
      )

      create(:push,
        after:      "9d4fd8fac2e227e78b79aeac35abb1aed5660d0a",
        before:     "9d4fd8fac2e227e78b79aeac35abb1aed5660d0c",
        ref:        "refs/heads/master",
        repository_id: repo.id,
        pusher_id: user.id,
        pushed_at: Time.now
      )

      create(:push,
        after:      "9d4fd8fac2e227e78b79aeac35abb1aed5660d0a",
        before:     "9d4fd8fac2e227e78b79aeac35abb1aed5660d0d",
        ref:        "refs/heads/master",
        repository_id: repo.id,
        pusher_id: user.id,
        pushed_at: Time.now
      )

      assert_equal "9d4fd8fac2e227e78b79aeac35abb1aed5660d0b",
        domain.first_before_sha_for(
          repository_id: repo.id,
          ref: "refs/heads/master",
          pusher_id: user.id,
          after: "9d4fd8fac2e227e78b79aeac35abb1aed5660d0a"
        )
    end
  end

  context "count" do
    test "returns a count of all pushes in db or raises error if caller is not enterprise or test suite" do
      create :push
      if GitHub.enterprise? || Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
        assert_equal 6, domain.count
      else
        assert_raises RuntimeError do
          domain.count
        end
      end
    end
  end
end
