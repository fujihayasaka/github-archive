# typed: true
# frozen_string_literal: true

require "test_helper"

class CommitsCollectionRebaseTest < GitHub::TestCase
  include DogstatsTestHelpers
  include HydroTestHelpers

  fixtures do
    @repo = create(:repository)
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    example_repo :merge_ort, @repo
    reset_cache
    @collection = CommitsCollection.new(@repo)
    @commit_time = Time.find_zone("UTC").local(2022, 1, 1)
  end

  def rebase(commit_oid, upstream_commit_oid, **kwargs)
    kwargs[:commit_time] = @commit_time if !kwargs[:commit_time]

    @collection.rebase(commit_oid, upstream_commit_oid, **kwargs)
  end

  def create_merge_commit(base_ref_name, head_ref_name, **kwargs)
    @collection.create_merge_commit(@repo.owner, base_ref_name, head_ref_name, **kwargs)
  end

  def oid(name)
    @repo.refs.find(name).target.oid
  end

  def tree_oid(name)
    @repo.refs.find(name).target.tree_oid
  end

  context "experiment" do
    test "tmp_objdir_experiment" do
      example_repo_snapshot

      GitHub.flipper[:tmp_objdir_experiment].enable
      GitHub.flipper[:tmp_objdir_experiment_pack].disable
      rebased, error = rebase(
        oid("pr-regular-merge-1"),
        oid("main-regular-merge-1"),
      )

      assert_dogstats_count_value(2, "rebase.loose_objects_count", tags: ["status:success"])
      assert_dogstats_count_value(2, "rebase.loose_objects_count_delta", tags: ["status:success"])
      assert_dogstats_count_value(0, "rebase.packfiles_count_delta", tags: ["status:success"])

      example_repo_restore
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      GitHub.flipper[:tmp_objdir_experiment_pack].enable
      GitHub.flipper[:tmp_objdir_experiment_threshold].disable_percentage_of_time
      rebased, error = rebase(
        oid("pr-regular-merge-1"),
        oid("main-regular-merge-1"),
      )

      assert_dogstats_count_value(0, "rebase.loose_objects_count_delta", tags: ["status:success"])
      assert_dogstats_count_value(1, "rebase.packfiles_count_delta", tags: ["status:success"])

      example_repo_restore
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      GitHub.flipper[:tmp_objdir_experiment_pack].enable
      GitHub.flipper[:tmp_objdir_experiment_threshold].enable_percentage_of_time(5)
      rebased, error = rebase(
        oid("pr-regular-merge-1"),
        oid("main-regular-merge-1"),
      )

      assert_dogstats_count_value(2, "rebase.loose_objects_count_delta", tags: ["status:success"])
      assert_dogstats_count_value(0, "rebase.packfiles_count_delta", tags: ["status:success"])
    end

    test "rebase_limit_loose_objects" do
      # 0.001% of 100k objects is 1 object. The rebase would need to write 2 objects, though
      GitHub.flipper[:rebase_limit_loose_objects].enable_percentage_of_time(0.001)
      assert_raises(GitRPC::Backend::RebaseTimeout) do
        rebase(
          oid("pr-regular-merge-1"),
          oid("main-regular-merge-1"),
        )
      end

      GitHub.flipper[:rebase_limit_loose_objects].disable_percentage_of_time
      assert_nothing_raised do
        rebase(
          oid("pr-regular-merge-1"),
          oid("main-regular-merge-1"),
        )
      end
    end
  end

  test "regular rebase: PR branch with commits ahead of base branch" do
    Timecop.freeze do
      with_hydro_publisher(GitHub.sync_hydro_publisher) do
        rebased, error = rebase(
          oid("pr-regular-merge-1"),
          oid("main-regular-merge-1"),
        )

        assert_nil error
        assert_equal rebased.tree_oid, tree_oid("pr-regular-merge-1")

        assert_hydro_published({
          repository_id: @repo.id,
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          created_at: Time.now,
          commit_shas: [rebased.oid],
          start_sha: nil,
          end_sha: nil,
          user_login: nil,
          enabled_flags: Repositories::HydroPushJobFlags::FLAGS.select { |f| GitHub.flipper[f].enabled? }
        }, schema: "github.repositories.v1.CommitsCreated", partition_key: @repo.id)

        assert_hydro_messages(count: 1, schema: "github.repositories.v1.CommitsCreated")
      end
    end
  end

  test "regular rebase: PR branch with merge commits that need to be skipped" do
    rebased, error = rebase(
      oid("criss-cross-merge-left"),
      oid("criss-cross-merge-right")
    )

    assert_nil error
    assert_equal rebased.oid, oid("criss-cross-merge-right")
  end

  test "regular rebase: actually rebase one commit" do
    rebased, error = rebase(
      oid("pr-regular-merge-2"),
      oid("main-regular-merge-2")
    )

    assert_nil error
    assert_equal rebased.parent_oids.length, 1
    assert_equal rebased.parent_oids[0], oid("main-regular-merge-2")
    refute_equal rebased.oid, oid("pr-regular-merge-2")

    # compare to merge
    merged, error = create_merge_commit(
      "pr-regular-merge-2",
      "main-regular-merge-2"
    )

    assert_nil error
    assert_equal rebased.tree_oid, merged.tree_oid
  end

  test "regular rebase: conflicts abort the rebase" do
    with_hydro_publisher(GitHub.sync_hydro_publisher) do
      rebased, error = rebase(
        oid("pr-conflict-10"),
        oid("main-conflict-10")
      )

      assert_nil rebased
      assert_equal :merge_conflict, error

      refute_hydro_messages(schema: "github.repositories.v1.CommitsCreated")
    end
  end
end
