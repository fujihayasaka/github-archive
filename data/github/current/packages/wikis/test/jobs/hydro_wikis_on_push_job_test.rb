# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroWikisOnPushJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include HydroTestHelpers

  fixtures do
    @pusher = create(:user, login: "defunkt")

    @orig_sha, @created_sha, @update_sha, @del_sha, @last_sha, @ren_sha, @add_np_sha, @mod_np_sha = %w(
      88d596906ef149c4e0fa4cd1b7c830193cfef3c2
      01038e231b2a9c6dd3b57e0a250bd86b14211289
      4fb665891b744d56e394db0559630343edceb8c6
      c604cf3c8f84fbaf2b2152d579a7a02f9b24ccf0
      7860026e5f00a37c32ce002b76826e3040f8904d
      4108391d2f2e5accd2234c6e160c288c88b14f53
      3af16e6aa7269c902291bf0ec2fb639cea18594a
      39e75c9b83a8c9154ebdc8759e4578411594c51f)

    @refs = [["refs/heads/master", @orig_sha, @created_sha],
             ["refs/heads/foo", @orig_sha, @created_sha],
             ["refs/heads/bar", @orig_sha, @created_sha],
            ]

    @wiki_user = create(:user)
    @wiki_repo = create(:repository, name: "wiki-receive-test", owner: @wiki_user, from_example: :simple)
    wiki = @wiki_repo.unsullied_wiki
    example_repo :wiki_receive, wiki

    create :user, email: "technoweenie@gmail.com"
    create :user, email: "rick@github.com"
  end

  setup do
    @message = {
      repository_id: @wiki_repo.id,
      ref_updates: @refs.map { |u| { ref: u[0], before: u[1], after: u[2] } },
      pushed_at: Time.current,
      pusher: @pusher.login,
      path: @wiki_repo.shard_path.sub(".git", ".wiki.git")
    }

    Spokesd.enable_spokesd
    DGit.bless @wiki_repo
    T.unsafe(GitHub).reset_stratocaster
    Elastomer::Indexes::CodeSearch.any_instance.stubs(:indexed_head).returns(nil)


    @created_message = {
      repository_id: @wiki_repo.id,
      ref_updates: [{ ref: "refs/heads/master", before: @orig_sha, after: @created_sha }],
      pushed_at: Time.current,
      pusher: @wiki_user.login,
      path: @wiki_repo.shard_path.sub(".git", ".wiki.git")
    }

    @updated_message = {
      repository_id: @wiki_repo.id,
      ref_updates: [{ ref: "refs/heads/master", before: @created_sha, after: @update_sha }],
      pushed_at: Time.current,
      pusher: @wiki_user.login,
      path: @wiki_repo.shard_path.sub(".git", ".wiki.git")
    }

    @deleted_message = {
      repository_id: @wiki_repo.id,
      ref_updates: [{ ref: "refs/heads/master", before: @update_sha, after: @del_sha }],
      pushed_at: Time.current,
      pusher: @wiki_user.login,
      path: @wiki_repo.shard_path.sub(".git", ".wiki.git")
    }

    @ren_message = {
      repository_id: @wiki_repo.id,
      ref_updates: [{ ref: "refs/heads/master", before: @last_sha, after: @ren_sha }],
      pushed_at: Time.current,
      pusher: @wiki_user.login,
      path: @wiki_repo.shard_path.sub(".git", ".wiki.git")
    }

    @add_np_message = {
      repository_id: @wiki_repo.id,
      ref_updates: [{ ref: "refs/heads/master", before: @ren_sha, after: @add_np_sha }],
      pushed_at: Time.current,
      pusher: @wiki_user.login,
      path: @wiki_repo.shard_path.sub(".git", ".wiki.git")
    }

    @mod_np_message = {
      repository_id: @wiki_repo.id,
      ref_updates: [{ ref: "refs/heads/master", before: @add_np_sha, after: @mod_np_sha }],
      pushed_at: Time.current,
      pusher: @wiki_user.login,
      path: @wiki_repo.shard_path.sub(".git", ".wiki.git")
    }

    @first_commit_message = {
      repository_id: @wiki_repo.id,
      ref_updates: [{ ref: "refs/heads/master", before: @add_np_sha, after: @orig_sha }],
      pushed_at: Time.current,
      pusher: @wiki_user.login,
      path: @wiki_repo.shard_path.sub(".git", ".wiki.git")
    }

    @deleted_branch_message = {
      repository_id: @wiki_repo.id,
      ref_updates: [{ ref: "refs/heads/master", before: @add_np_sha, after: GitHub::NULL_OID }],
      pushed_at: Time.current,
      pusher: @wiki_user.login,
      path: @wiki_repo.shard_path.sub(".git", ".wiki.git")
    }

    @created_tag_message = {
      repository_id: @wiki_repo.id,
      ref_updates: [{ ref: "refs/tags/v1.0", before: GitHub::NULL_OID, after: "4ffb9c917bcbe5a2afbc22ed1554277ad9002191" }],
      pushed_at: Time.current,
      pusher: @wiki_user.login,
      path: @wiki_repo.shard_path.sub(".git", ".wiki.git")
    }
  end

  test "publishes wiki hydro event" do
    wiki_message = {
      user: @wiki_repo.owner.login,
      pusher: @pusher.login,
    }

    assert_hydro_messages(count: 0, schema: "github.v1.WikiPostReceive")

    Timecop.freeze do
      perform_hydro_message_job(@message.merge({ pushed_at: Time.current }), schema: "github.repositories.v1.Pushed", queue: "hydro_wikis_on_push")

      expected_hydro_event_ref_updates = @refs.map do |(ref, before, after)|
        {
          ref_name: ref&.dup&.force_encoding(Encoding::UTF_8),
          previous_ref_oid: before,
          current_ref_oid: after,
        }
      end

      expected_hydro_message = {
        pusher: Hydro::EntitySerializer.user(@pusher),
        owner: Hydro::EntitySerializer.user(@wiki_repo.owner),
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        repository: Hydro::EntitySerializer.repository(@wiki_repo),
        wiki_world_writable: false,
        ref_updates: Array.wrap(expected_hydro_event_ref_updates),
        feature_flags: TestEnv.test_all_features? ? @wiki_repo.post_receive_instrumentation_feature_flags : [],
        pushed_at: Time.current,
        business_id: @wiki_repo.owner.business&.id,
      }

      assert_hydro_published(expected_hydro_message, schema: "github.v1.WikiPostReceive")
      assert_hydro_messages(count: 1, schema: "github.v1.WikiPostReceive")
    end
  end

  test "adds :create GollumEvent for added page" do
    perform_enqueued_jobs(only: [ProcessEventJob]) do
      perform_hydro_message_job(@created_message, schema: "github.repositories.v1.Pushed", queue: "hydro_wikis_on_push")
    end
    assert evt = GitHub.stratocaster_store.last
    assert_equal "created",     evt.payload["pages"].last["action"].to_s
    assert_equal "GollumEvent", evt.event_type
    assert_equal "file",        evt.payload["pages"].last["page_name"]
  end

  test "adds :create GollumEvent for first commit" do
    perform_enqueued_jobs(only: [ProcessEventJob]) do
      perform_hydro_message_job(@first_commit_message, schema: "github.repositories.v1.Pushed", queue: "hydro_wikis_on_push")
    end
    assert evt = GitHub.stratocaster_store.last
    assert_equal "created",     evt.payload["pages"].last["action"].to_s
    assert_equal "GollumEvent", evt.event_type
    assert_equal "home",        evt.payload["pages"].last["page_name"]
  end

  test "adds no GollumEvent for deleted page" do
    perform_enqueued_jobs(only: [ProcessEventJob]) do
      perform_hydro_message_job(@deleted_message, schema: "github.repositories.v1.Pushed", queue: "hydro_wikis_on_push")
    end
    assert_nil GitHub.stratocaster_store.last
  end

  test "adds :edited GollumEvent for updated page" do
    perform_enqueued_jobs(only: [ProcessEventJob]) do
      perform_hydro_message_job(@updated_message, schema: "github.repositories.v1.Pushed", queue: "hydro_wikis_on_push")
    end
    assert evt = GitHub.stratocaster_store.last
    assert_equal "edited",      evt.payload["pages"].last["action"].to_s
    assert_equal "GollumEvent", evt.event_type
    assert_equal "home",        evt.payload["pages"].last["page_name"]
  end

  test "adds :edited GollumEvent for renamed page" do
    perform_enqueued_jobs(only: [ProcessEventJob]) do
      perform_hydro_message_job(@ren_message, schema: "github.repositories.v1.Pushed", queue: "hydro_wikis_on_push")
    end
    assert evt = GitHub.stratocaster_store.last
    assert_equal "edited",      evt.payload["pages"].last["action"].to_s
    assert_equal "GollumEvent", evt.event_type
    assert_equal "Home",        evt.payload["pages"].last["page_name"]
  end

  test "adds GollumEvent when default branch is not master" do
    @wiki_repo.update_attribute(:default_branch, "deploy")
    perform_enqueued_jobs(only: [ProcessEventJob]) do
      perform_hydro_message_job(@created_message, schema: "github.repositories.v1.Pushed", queue: "hydro_wikis_on_push")
    end
    assert evt = GitHub.stratocaster_store.last
    assert_equal "GollumEvent", evt.event_type
  end

  test "adds no GollumEvent for non-master branch" do
    @created_message[:ref_updates][0][:ref] = "refs/heads/test"
    perform_enqueued_jobs(only: [ProcessEventJob]) do
      perform_hydro_message_job(@created_message, schema: "github.repositories.v1.Pushed", queue: "hydro_wikis_on_push")
    end
    assert_nil GitHub.stratocaster_store.last
  end

  test "ignores new non-page files" do
    @add_np_message[:ref_updates][0][:ref] = "refs/heads/test"
    perform_enqueued_jobs(only: [ProcessEventJob]) do
      perform_hydro_message_job(@add_np_message, schema: "github.repositories.v1.Pushed", queue: "hydro_wikis_on_push")
    end
    assert_nil GitHub.stratocaster_store.last
  end

  test "ignores modified non-page files" do
    @mod_np_message[:ref_updates][0][:ref] = "refs/heads/test"
    perform_enqueued_jobs(only: [ProcessEventJob]) do
      perform_hydro_message_job(@mod_np_message, schema: "github.repositories.v1.Pushed", queue: "hydro_wikis_on_push")
    end
    assert_nil GitHub.stratocaster_store.last
  end

  test "doesn't explode when deleting a branch" do
    perform_enqueued_jobs(only: [ProcessEventJob]) do
      perform_hydro_message_job(@deleted_branch_message, schema: "github.repositories.v1.Pushed", queue: "hydro_wikis_on_push")
    end
  end

  test "doesn't explode when pushing a tag" do
    perform_enqueued_jobs(only: [ProcessEventJob]) do
      perform_hydro_message_job(@created_tag_message, schema: "github.repositories.v1.Pushed", queue: "hydro_wikis_on_push")
    end
  end

  test "bumps wiki push counts" do
    assert_difference(
      -> { RepositoryWiki.find_by!(repository: @wiki_repo).pushed_count } => 1,
      -> { RepositoryWiki.find_by!(repository: @wiki_repo).pushed_count_since_maintenance } => 1,
    ) do
      perform_hydro_message_job(@message, schema: "github.repositories.v1.Pushed", queue: "hydro_wikis_on_push")
    end
  end

  test "is a no-op for a non wiki push" do
    HydroWikisOnPushJob.any_instance.expects(:create_wiki_events).never

    message = @message.merge(path: @wiki_repo.shard_path)
    perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_wikis_on_push")
  end
end
