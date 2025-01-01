# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class HydroRepositoriesOnPushJobTest < GitHub::TestCase
  include DogstatsTestHelpers
  include HydroMessageJobTestHelpers
  include GitHub::LoggerHelper
  include HydroTestHelpers
  include PushTestHelper

  Spokesd.share_spokesdb(self)

  fixtures do
    @user = create(:user)
    @repository = create(:repository, owner: @user)

    @org = create(:organization, plan: GitHub::Plan.business_plus)
    @aleph_repo = create(:public_repository, owner: @org, from_example: :tagsearch)
    @aleph_repo.analyze_languages
  end

  setup do
    Spokesd.enable_spokesd

    GitHub.flipper[:discard_stratocaster_fanout].disable

    example_repo :post_receive_job_test, @repository

    @commit_sha_before = "c1800491d95c42b4e96fb83f31fe8d9230c62907"
    @commit_sha_after = "63611721afd41f58f801d66e543d8288b4c5eb44"

    @ref = "refs/heads/master"
    @updates = [Git::Ref::Update.new(repository: @repository, refname: @ref, before_oid: @commit_sha_before, after_oid: @commit_sha_after)]

    @time = Time.now
    @message = {
      repository_id: @repository.id,
      request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
      ref_updates: @updates.map { |u| { ref: u.refname, before: u.before_oid, after: u.after_oid } },
      pushed_at: @time,
      pusher: @user.login,
      run_hydro_job: true,
      enabled_flags: Repositories::HydroPushJobFlags::FLAGS.select { |f| GitHub.flipper[f].enabled? },
    }

    @pusher = create(:user)
    @post_receive_message = {
      repository_id: @repository.id,
      request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
      ref_updates: { ref: "refs/heads/master", before: "c1800491d95c42b4e96fb83f31fe8d9230c62907", after: "63611721afd41f58f801d66e543d8288b4c5eb44" },
      pushed_at: 1.minute.ago,
      pusher: @pusher.login,
    }

    @aleph_test_before = "0000000000000000000000000000000000000000"
    @aleph_test_after = "a2dd592cccfba2bdf56e09161497e12411604a2e"
    @aleph_message = {
      repository_id: @aleph_repo.id,
      request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
      ref_updates: [{ ref: @ref, before: @aleph_test_before, after: @aleph_test_after }],
      pushed_at: Time.now,
      pusher: @user.login,
      enabled_flags: Repositories::HydroPushJobFlags::FLAGS.select { |f| GitHub.flipper[f].enabled? },
    }

    @aleph_hydro_message = {
      actor: Hydro::EntitySerializer.user(@user),
      owner: Hydro::EntitySerializer.user(@org, overrides: { type: :ORGANIZATION, analytics_tracking_id: @org.analytics_tracking_id }),
      before: @aleph_test_before,
      after: @aleph_test_after,
      ref: @ref,
      forced: false,
      large: false,
      commit_count: 1,
      commit_oids: ["a2dd592cccfba2bdf56e09161497e12411604a2e"],
      branch_protection_rule: nil,
      request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
      tree_oid: "9045a750aefb01a7d318acdf5a52639a20733a06",
    }
  end

  test "it works" do
    perform_hydro_message_job(@message, schema: "github.repositories.v1.Pushed", queue: "hydro_repositories_on_push")
    assert_dogstats_increment 1, "hydro_repositories_on_push_job.perform"
  end

  test "discards with message" do
    Repository.any_instance.stubs(:exists_on_disk?).returns(false)

    expected_keys = {
      "Body": /Discarding push job. Reason: non-existent repo/,
      "code.namespace": "PushHydroMessageJob",
      "code.function": "discard_on",
      "exception.type": "Repositories::PushHydroMessageJob::DiscardJob"
    }
    assert_logged(**expected_keys) do
      perform_hydro_message_job(@message, schema: "github.repositories.v1.Pushed", queue: "hydro_repositories_on_push")
    end

    assert_dogstats_increment 0, "hydro_repositories_on_push_job.perform"
    assert_dogstats_increment 1, "github.hydro_message_job.discarded"
  end

  test "pushes a metric for author count to datadog" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    perform_hydro_message_job(@post_receive_message, schema: "github.repositories.v1.Pushed", queue: "hydro_repositories_on_push")

    assert_equal 2, GitHub.dogstats.histograms("commit.authors").count
  end

  test "publishes an event containing commit data" do
    @post_receive_message[:ref_updates][:ref]    = "refs/heads/master"
    @post_receive_message[:ref_updates][:before] = "63611721afd41f58f801d66e543d8288b4c5eb44"
    @post_receive_message[:ref_updates][:after]  = "94492bb7f7b72fda43ba7934a91edeffe6bc814a"

    payloads = T.let([], T.untyped)
    subscriber = GlobalInstrumenter.subscribe("repository.post_receive_commits") do |_, _, _, _, payload|
      payloads << payload
    end

    perform_hydro_message_job(@post_receive_message, schema: "github.repositories.v1.Pushed", queue: "hydro_repositories_on_push")

    GlobalInstrumenter.notifier.unsubscribe(subscriber)

    assert_equal 1, payloads.size

    expected_commits = @repository.commits.find(@repository.rpc.rev_list("94492bb7f7b72fda43ba7934a91edeffe6bc814a").take(2)).reverse
    assert_equal expected_commits, payloads.first[:commits]
  end

  test "resetting the default branch when deleted" do
    other_branch = (@repository.heads.names - ["topic"]).first

    @repository.update_default_branch("topic")
    assert_equal "topic", @repository.default_branch

    @post_receive_message[:ref_updates][:ref]    = "refs/heads/topic"
    @post_receive_message[:ref_updates][:after]  = GitHub::NULL_OID
    perform_hydro_message_job(@post_receive_message, schema: "github.repositories.v1.Pushed", queue: "hydro_repositories_on_push")
    assert_equal other_branch, @repository.reload.default_branch
  end

  test "Necessary methods in HydroRepositoriesOnPushJob are called" do
    HydroRepositoriesOnPushJob.any_instance.expects(:notify_ref_socket_subscribers)

    HydroRepositoriesOnPushJob.any_instance.expects(:update_websocket)

    HydroRepositoriesOnPushJob.any_instance.expects(:index_readme)
    HydroRepositoriesOnPushJob.any_instance.expects(:index_source_code)
    HydroRepositoriesOnPushJob.any_instance.expects(:index_commits)

    HydroRepositoriesOnPushJob.any_instance.expects(:notify_mentioned)
    HydroRepositoriesOnPushJob.any_instance.expects(:publish_commits_pushed)
    HydroRepositoriesOnPushJob.any_instance.expects(:record_author_count)

    perform_hydro_message_job(@post_receive_message, schema: "github.repositories.v1.Pushed", queue: "hydro_repositories_on_push")
    # implicitly asserts that `index_commits` and `publish_commits_pushed` are called
  end

  test "Necessary methods in HydroRepositoriesOnPushJob are called on delete" do
    @post_receive_message[:ref_updates][:after] = GitHub::NULL_OID

    Repository.any_instance.expects(:ref_deleted)

    perform_hydro_message_job(@post_receive_message, schema: "github.repositories.v1.Pushed", queue: "hydro_repositories_on_push")
  end

  test "Creates commit mentions" do
    mention_user = create(:user)
    commit_data = {
      message: "Push file @#{mention_user.login}",
      committer: @user,
    }

    ref = @repository.default_branch_ref

    commit = ref.append_commit(commit_data, @user) do |files|
      files.add("test", "Test content :)")
    end

    @post_receive_message[:ref_updates][:after] = commit.oid

    assert_difference "CommitMention.count", 1 do
      perform_hydro_message_job(@post_receive_message, schema: "github.repositories.v1.Pushed", queue: "hydro_repositories_on_push")
    end

    commit_mention = CommitMention.find_by(commit_id: commit.oid)
    assert_equal mention_user.login, commit_mention&.mentioned_users.first.login
  end

  test "Successfully pushes to a branch with an emoji" do
    GitHub.stubs(:live_updates_enabled?).returns(true)

    @post_receive_message[:ref_updates][:ref] = "refs/heads/💔"

    perform_hydro_message_job(@post_receive_message, schema: "github.repositories.v1.Pushed", queue: "hydro_repositories_on_push")
    # publishing from HydroRepositoriesOnPushJob#update_websocket and HydroRepositoriesOnPushJob#notify_ref_socket_subscribers
    assert_hydro_messages(count: 2, schema: "live_updates.v0.Message")
  end

  context "pushing a wiki" do
    test "skips post receive methods" do
      HydroRepositoriesOnPushJob.any_instance.expects(:notify_ref_socket_subscribers).never
      HydroRepositoriesOnPushJob.any_instance.expects(:update_websocket).never
      HydroRepositoriesOnPushJob.any_instance.expects(:index_readme).never
      HydroRepositoriesOnPushJob.any_instance.expects(:index_source_code).never
      HydroRepositoriesOnPushJob.any_instance.expects(:index_commits).never
      HydroRepositoriesOnPushJob.any_instance.expects(:notify_mentioned).never
      HydroRepositoriesOnPushJob.any_instance.expects(:publish_commits_pushed).never
      HydroRepositoriesOnPushJob.any_instance.expects(:record_author_count).never
      HydroRepositoriesOnPushJob.any_instance.expects(:deliver_ref_create_delete_webhooks).never

      @post_receive_message[:path] = @repository.wiki_path
      perform_hydro_message_job(@post_receive_message, schema: "github.repositories.v1.Pushed", queue: "hydro_repositories_on_push")
    end
  end

  test "queues RepositoryCheckPreferredFilesJob" do
    message = @message.merge({
      ref_updates: [{ ref: @ref, before: GitHub::NULL_OID, after: @commit_sha_after }],
    })

    assert_enqueued_with job: RepositoryCheckPreferredFilesJob do
      perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_repositories_on_push")
    end
  end

  test "queues RepositorySetLicenseJob when a push changes a standard license file" do
    message = @message.merge({
      ref_updates: [{ ref: @ref, before: GitHub::NULL_OID, after: @commit_sha_after }]
    })

    Push.any_instance.stubs(:license_changed?).returns(true)
    assert_enqueued_with job: RepositorySetLicenseJob do
      perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_repositories_on_push")
    end
  end

  test "large pushes skip expensive work" do
    message = @message.merge({
      ref_updates: [{ ref: @ref, before: GitHub::NULL_OID, after: @commit_sha_after }],
    })

    # skips skippable things
    HydroRepositoriesOnPushJob.any_instance.stubs(:large_push?).returns(true)
    HydroRepositoriesOnPushJob.any_instance.expects(:notify_mentioned).never
    HydroRepositoriesOnPushJob.any_instance.expects(:publish_commits_pushed).never
    HydroRepositoriesOnPushJob.any_instance.expects(:record_author_count).never
    HydroRepositoriesOnPushJob.any_instance.expects(:update_websocket).never
    Repositories::RefUpdate.any_instance.expects(:large_push?).never

    # still performs a couple things for default branch updates
    HydroRepositoriesOnPushJob.any_instance.expects(:index_readme).once
    HydroRepositoriesOnPushJob.any_instance.expects(:integrate_issues).never

    perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_repositories_on_push")
  end

  context "Stratocaster PushEvent" do
    test "creates a Stratocaster PushEvent" do
      user = create(:user)
      user.watch_repo(@repository)

      only = [ProcessEventJob, UpdateEventFeedsJob]
      perform_enqueued_jobs(only: only) do
        perform_hydro_message_job(@message, schema: "github.repositories.v1.Pushed", queue: "hydro_repositories_on_push")
      end

      push = @repository.pushes.first

      assert event = GitHub.stratocaster.events("repo:#{@repository.id}").detect { |e| e.event_type == "PushEvent" }
      assert_equal "refs/heads/master", event.payload["ref"]
      assert_equal @commit_sha_before, event.payload["before"]
      assert_equal @commit_sha_after, event.payload["head"]
      assert_equal push.id, event.payload["push_id"]
      assert event.public?
      assert_match "/#{@repository.nwo}/compare/#{@commit_sha_before[0, 10]}...#{@commit_sha_after[0, 10]}", event.url
      assert_equal 0, event.payload["distinct_size"]
      assert_equal 2, event.payload["commits"].size
      assert_equal 2, event.payload["legacy"]["shas"].size
      assert_equal "rick", event.payload["commits"].first["author"]["name"]
      assert_equal "rick", event.payload["legacy"]["shas"].first[3]

      targets = Stratocaster.attributes_class_for(event.event_type).from_event(event).targets
      assert_equal @repository.watchers.size, targets.size
    end
  end

  context "dependency graph" do
    test "changed manifest files enqueue a changed job if manifests have been detected" do
      if GitHub.enterprise?
        GitHub.stubs(
          dependency_graph_enabled?: true,
          dotcom_connection_enabled?: true,
          ghe_content_analysis_enabled?: true,
        )
      end

      before, after = commit_changes(repository: @repository, changes: { path: "Gemfile", content: "gem 'foo'" })
      message = @message.merge({ ref_updates: [{ ref: @ref, before: before, after: after }] })
      perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_repositories_on_push")
      push = @repository.pushes.first
      assert_enqueued_with job: RepositoryDependencyManifestChangedJob, args: ->(args) do
        args[0] == push.id
        args[1] == push.repository_id
      end
    end

    test "unchanged manifest files don't enqueue a job" do
      before, after = commit_changes(repository: @repository, changes: { path: "README", content: "# Header" })
      message = @message.merge({ ref_updates: [{ ref: @ref, before: before, after: after }] })
      perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_repositories_on_push")
      assert_no_enqueued_jobs only: RepositoryDependencyManifestChangedJob
    end

    unless GitHub.enterprise?
      test "changed manifest files request a snapshot on a non-default branch" do
        before, after = commit_changes(repository: @repository, branch_name: "development", create_branch: true,  changes: { path: "Gemfile", content: "gem 'foo'" })
        message = @message.merge({ ref_updates: [{ ref: "refs/heads/development", before: before, after: after }] })
        perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_repositories_on_push")

        push = @repository.pushes.first
        expected_files = push.changed_files.collect do |file|
          {
            filename: File.basename(file.path),
            path: File.dirname(file.path).sub(/\A\.\z/, ""),
            blob_oid: file.oid,
          }
        end

        assert_hydro_published({
            push_id: push.id,
            before_sha: push.before,
            sha: push.after,
            ref: push.ref,
            pushed_at: push.created_at,
            owner_name: @repository.owner.login,
            manifest_files: expected_files
          },
          schema: "github.dependencygraph.v0.RequestPushSnapshot",
          ignore_extra_keys: true
        )
      end
    end
  end

  context "CheckSuites" do
    test "enqueues the check suite creation job" do
      github_app   = create :integration, default_permissions: { "checks" => :write }
      installation = make_integration_installation integration: @github_app, repository: @repository

      message = @message.merge({ ref_updates: [{ ref: @ref, before: "4c8124ffcf4039d292442eeccabdeca5af5c5017", after: "a47fd41f3aa4610ea527dcc1669dfdb9c15c5425" }] })
      perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_repositories_on_push")

      push = @repository.pushes.first
      assert_enqueued_with job: CreateCheckSuitesJob, queue: "create_check_suites", args: [push.id, push.repository_id]
    end

    test "skips check suite creation if push represents a ref being deleted" do
      @github_app   = create :integration, default_permissions: { "checks" => :write }
      @installation = make_integration_installation integration: @github_app, repository: @repository

      message = @message.merge({ ref_updates: [{ ref: "refs/heads/some-topic", before: "4c8124ffcf4039d292442eeccabdeca5af5c5017", after: GitHub::NULL_OID }] })

      assert_enqueued_jobs 0, only: CreateCheckSuitesJob, queue: :create_check_suites do
        perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_repositories_on_push")
      end
    end

    test "skips check suite creation if last commit contains both 'skip-checks' AND 'request-checks' as true" do
      commit_message = <<~MSG
        so confused

        skip-checks: true
        request-checks: true
      MSG

      ref = @repository.heads.find("master")
      before = ref.target_oid
      commit = ref.append_commit({ message: commit_message, committer: @user }, @user) do |files|
        files.add("blah.txt", "some contents")
      end

      message = @message.merge({ ref_updates: [{ ref: @ref, before: before, after: commit.sha }] })

      commit = @repository.refs["master"].commit
      assert_equal "true", commit.skip_checks
      assert_equal "true", commit.request_checks

      assert_enqueued_jobs 0, only: CreateCheckSuitesJob, queue: :create_check_suites do
        perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_repositories_on_push")
      end
    end

    test "resolves tenant for check suite creation" do
      on_multi_tenant_enterprise do
        user = create(:emu)
        GitHub::CurrentTenant.set(user.enterprise_managed_business)
        repo = create(:repository, owner: user, from_example: :simple)

        GitHub::CurrentTenant.remove
        assert_nil GitHub::CurrentTenant.get

        CreateCheckSuitesJob.perform_now(0, repo.id)
        assert_equal repo.reload.tenant_id, GitHub::CurrentTenant.get.id
      end
    end
  end

  test "instruments repository.push hydro event when push is created" do
    mojombo = create(:user, login: "mojombo",  plan: "medium")
    grit    = create(:repository, name: "github", owner: mojombo, from_example: :mojombo_grit)

    assert_hydro_messages(count: 0, schema: "github.v1.RepositoryPush")

    before = "4c8124ffcf4039d292442eeccabdeca5af5c5017"
    after = "a47fd41f3aa4610ea527dcc1669dfdb9c15c5425"
    message = @message.merge({
      ref_updates: [{ ref: @ref, before:, after: }],
      push_options: Hydro::EntitySerializer.push_options(["pull.ready"]),
      pusher: mojombo.login,
      repository_id: grit.id
    })
    perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_repositories_on_push")

    push = T.must(push_accessor.latest_by_after_and_ref(repository_id: grit.id, after: after, ref: @ref))

    hydro_message = {
      repository: Hydro::EntitySerializer.repository(push.repository),
      actor: Hydro::EntitySerializer.user(mojombo),
      owner: Hydro::EntitySerializer.user(mojombo),
      before: before,
      after: after,
      ref: @ref,
      changed_files: push.changed_files&.map { |f| Hydro::EntitySerializer.changed_file(f) },
      push_id: push.id,
      forced: false,
      large: false,
      commit_count: 0,
      commit_oids: %w[
        06f63b43050935962f84fe54473a7c5de7977325
        5057e76a11abd02e83b7d3d3171c4b68d9c88480
        a47fd41f3aa4610ea527dcc1669dfdb9c15c5425
      ],
      branch_protection_rule: nil,
      request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
      tree_oid: Hydro::EntitySerializer.repository_tree_oid_for_branch(grit, push.branch_name),
      push_options: [:PULL_READY]
    }

    if GitHub.flipper[:repo_on_push_hydro_forwarder].enabled?
      with_hydro_publisher(GitHub.sync_hydro_publisher) do
        assert_hydro_published(hydro_message, schema: "github.v1.RepositoryPush", partition_key: grit.id)
      end
    else
      assert_hydro_published(hydro_message, schema: "github.v1.RepositoryPush", partition_key: grit.id)
    end
  end

  context "RepositoryPush event for aleph" do
    test "message includes no feature flag values" do
      GitHub.flipper[:aleph_language_ruby].enable
      assert_hydro_messages(count: 0, schema: "github.v1.RepositoryPush")
      perform_hydro_message_job(@aleph_message, schema: "github.repositories.v1.Pushed", queue: "hydro_repositories_on_push")

      push = T.must(push_accessor.latest_by_after_and_ref(repository_id: @aleph_repo.id, after: @aleph_test_after, ref: @ref))

      @aleph_hydro_message[:feature_flags] = []
      @aleph_hydro_message[:changed_files] = push.changed_files&.map { |f| Hydro::EntitySerializer.changed_file(f) }
      @aleph_hydro_message[:push_id] = push.id
      @aleph_hydro_message[:repository] = Hydro::EntitySerializer.repository(@aleph_repo.reload)

      if GitHub.flipper[:repo_on_push_hydro_forwarder].enabled?
        with_hydro_publisher(GitHub.sync_hydro_publisher) do
          assert_hydro_published(@aleph_hydro_message, schema: "github.v1.RepositoryPush", partition_key: @aleph_repo.id)
        end
      else
        assert_hydro_published(@aleph_hydro_message, schema: "github.v1.RepositoryPush", partition_key: @aleph_repo.id)
      end
    end

    test "message includes no feature flag values if indexing is disabled when darkship language indexing enabled" do
      GitHub.flipper[:aleph_language_ruby].remove
      GitHub.flipper[:aleph_darkship_language_ruby].enable

      assert_hydro_messages(count: 0, schema: "github.v1.RepositoryPush")

      perform_hydro_message_job(@aleph_message, schema: "github.repositories.v1.Pushed", queue: "hydro_repositories_on_push")
      push = T.must(push_accessor.latest_by_after_and_ref(repository_id: @aleph_repo.id, after: @aleph_test_after, ref: @ref))

      @aleph_hydro_message[:feature_flags] = []
      @aleph_hydro_message[:changed_files] = push.changed_files&.map { |f| Hydro::EntitySerializer.changed_file(f) }
      @aleph_hydro_message[:push_id] = push.id
      @aleph_hydro_message[:repository] = Hydro::EntitySerializer.repository(@aleph_repo.reload)

      if GitHub.flipper[:repo_on_push_hydro_forwarder].enabled?
        with_hydro_publisher(GitHub.sync_hydro_publisher) do
          assert_hydro_published(@aleph_hydro_message, schema: "github.v1.RepositoryPush", partition_key: @aleph_repo.id)
        end
      else
        assert_hydro_published(@aleph_hydro_message, schema: "github.v1.RepositoryPush", partition_key: @aleph_repo.id)
      end
    end
  end unless GitHub.enterprise?
end

# This class tests functionality in HydroRepositoriesOnPushJob by invoking the whole push processing pipline,
# beginning with publishing a push event and ending with the completion of the HydroRepositoriesOnPushJob.
class HydroRepositoriesOnPushJobIntegrationTest < GitHub::TestCase
  include HydroTestHelpers
  include JobTestHelper
  include DogstatsTestHelpers
  include HydroMessageJobTestHelpers
  include PushTestHelper

  fixtures do
    @user = create(:user, login: "tonystark")
    @pusher = create(:user, login: "defunkt")
    @repo = create(:repository, owner: @user, name: "repository-push-test")
    @repo.initialize_wiki(@repo.owner)
    @refs = [
        ["refs/heads/master", "4c8124ffcf4039d292442eeccabdeca5af5c5017", "a47fd41f3aa4610ea527dcc1669dfdb9c15c5425"],
        ["refs/heads/dead", "12521512512515325h4234v3c322323423423423", GitHub::NULL_OID],
        ["refs/heads/awesome", "5dea2f86730665894cf03f2b1fac98c1217a9fb4", "451a4d8118d2c9c746c687efceaacac799e67ad9"],
        ["refs/heads/lame", GitHub::NULL_OID, "251a4d8118d2c9c746c687efceaacac799e67ad9"]]

    @input = build_input @refs

    @message = {
      user: @user.login,
      repo: @repo.name,
      pusher: "defunkt",
    }

    @enabled_hydro_flags = TestEnv.test_all_features? ? Repositories::HydroPushJobFlags::FLAGS : []
  end

  setup do
    [*@repo.heads, *@repo.tags].each do |ref|
      ref.delete(@user)
    end
    @repo.update_default_branch_spokes("refs/heads/master")

    reset_cache
  end

  def perform_push_job(args, **kwargs)
    perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
      trigger_push_event(*args)
    end
  end

  context "maintenance of refset_updated_at" do
    test "on simple update (non-create/destroy) does nothing" do
      @repo.update_column("refset_updated_at", nil)
      push_test!(@repo.shard_path, [
        "4c8124ffcf4039d292442eeccabdeca5af5c5017",
        "a47fd41f3aa4610ea527dcc1669dfdb9c15c5425",
        "refs/heads/master"].join(" "))
      # need to assert against attributes and not the getter since the getter auto-backfills.
      assert_nil @repo.reload.attributes["refset_updated_at"]
    end

    test "on branch create, touches column" do
      @repo.update_column("refset_updated_at", nil)
      push_test!(@repo.shard_path, [
        GitHub::NULL_OID,
        "a47fd41f3aa4610ea527dcc1669dfdb9c15c5425",
        "refs/heads/i_made_this"].join(" "))
      # need to assert against attributes and not the getter since the getter auto-backfills.
      refute_nil @repo.reload.attributes["refset_updated_at"]
    end

    test "on branch delete, touches column" do
      @repo.update_column("refset_updated_at", nil)
      push_test!(@repo.shard_path, [
        "a47fd41f3aa4610ea527dcc1669dfdb9c15c5425",
        GitHub::NULL_OID,
        "refs/heads/it_was_a_bad_idea_anyway"].join(" "))
      # need to assert against attributes and not the getter since the getter auto-backfills.
      refute_nil @repo.reload.attributes["refset_updated_at"]
    end

    test "on tag create, touches column" do
      @repo.update_column("refset_updated_at", nil)
      push_test!(@repo.shard_path, [
        GitHub::NULL_OID,
        "a47fd41f3aa4610ea527dcc1669dfdb9c15c5425",
        "refs/tags/v1"].join(" "))
      # need to assert against attributes and not the getter since the getter auto-backfills.
      refute_nil @repo.reload.attributes["refset_updated_at"]
    end

    test "on tag delete, touches column" do
      @repo.update_column("refset_updated_at", nil)
      push_test!(@repo.shard_path, [
        "a47fd41f3aa4610ea527dcc1669dfdb9c15c5425",
        GitHub::NULL_OID,
        "refs/tags/v2"].join(" "))
      # need to assert against attributes and not the getter since the getter auto-backfills.
      refute_nil @repo.reload.attributes["refset_updated_at"]
    end

    test "mixed updates with no creations or deletions does not touch column" do
      @repo.update_column("refset_updated_at", nil)
      refs = [
        ["refs/heads/master", "4c8124ffcf4039d292442eeccabdeca5af5c5017", "a47fd41f3aa4610ea527dcc1669dfdb9c15c5425"],
        ["refs/heads/awesome", "5dea2f86730665894cf03f2b1fac98c1217a9fb4", "451a4d8118d2c9c746c687efceaacac799e67ad9"]
      ]
      push_test!(@repo.shard_path, build_input(refs))
      # need to assert against attributes and not the getter since the getter auto-backfills.
      assert_nil @repo.reload.attributes["refset_updated_at"]
    end

    test "mixed updates including creations or deletions touches column" do
      @repo.update_column("refset_updated_at", nil)
      refs = [
        ["refs/heads/master", "4c8124ffcf4039d292442eeccabdeca5af5c5017", "a47fd41f3aa4610ea527dcc1669dfdb9c15c5425"],
        ["refs/heads/dead", "12521512512515325h4234v3c322323423423423", GitHub::NULL_OID],
        ["refs/heads/awesome", "5dea2f86730665894cf03f2b1fac98c1217a9fb4", "451a4d8118d2c9c746c687efceaacac799e67ad9"],
        ["refs/heads/lame", GitHub::NULL_OID, "251a4d8118d2c9c746c687efceaacac799e67ad9"]
      ]
      push_test!(@repo.shard_path, build_input(refs))
      # need to assert against attributes and not the getter since the getter auto-backfills.
      refute_nil @repo.reload.attributes["refset_updated_at"]
    end
  end

  test "enqueues RepositoryDiskUsageJob for more than 3 tags" do
    refs = []
    5.times do |i|
      refs << ["refs/tags/#{i}", GitHub::NULL_OID, (i + 1).to_s * 40]
    end

    Timecop.freeze do
      RepositoryDiskUsageJob.expects(:enqueue_once_per_interval).with(args: [@repo.id], interval: 60 * 60)
      assert_no_difference -> { @repo.pushes.count } do
        push_test! @repo.shard_path, build_input(refs)
      end
    end
  end

  def push_job!(path, input = nil, pusher = "defunkt", merge_action: nil)
    ENV["GIT_PUSHER"] = pusher if pusher
    input ||= @input
    refs = input.split("\n").inject([]) do |list, line|
      before, after, ref = line.split(" ", 3)
      list << [ref, before, after]
    end

    perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
      trigger_push_event(path, pusher, refs, Time.current, merge_action:)
    end
  end

  def push_test!(path, input = nil, merge_action: nil)
    push_job!(path, input, merge_action:)
  ensure
    ENV.delete("GIT_PUSHER")
  end

  def anonymous_push_test!(path, input = nil)
    push_job!(path, input, nil)
  end

  def simple_push!
    push_test! @repo.shard_path, [
      GitHub::NULL_OID,
      "251a4d8118d2c9c746c687efceaacac799e67ad9",
      "refs/heads/master"].join(" ")
  end

  test "enqueues RepositoryUpdateLanguage job" do
    simple_push!
    assert_enqueued_jobs 1, only: RepositoryUpdateLanguageStatsJob, queue: :languages
  end

  test "enqueues no PreReceiveRepositoryUpdate if no hooks are present" do
    simple_push!
    assert_enqueued_jobs 0, only: PreReceiveRepositoryUpdateJob, queue: :pre_receive_repository_update
  end

  test "enqueues PreReceiveRepositoryUpdate if hooks are present" do
    PreReceiveHook.create name: "name1", repository: @repo, environment: create(:pre_receive_environment), script: "original_script.rb"
    simple_push!
    assert_enqueued_jobs 2, only: PreReceiveRepositoryUpdateJob, queue: :pre_receive_repository_update
  end

  test "doesn't enqueue RepositoryUpdateLanguage job for non-default-branch pushes" do
    push_test! @repo.shard_path, [
      GitHub::NULL_OID,
      "251a4d8118d2c9c746c687efceaacac799e67ad9",
      "refs/heads/blah"].join(" ")
    assert_enqueued_jobs 0, only: RepositoryUpdateLanguageStatsJob, queue: :pre_receive_repository_update
  end

  test "queueing backup job" do
    assert_enqueued_jobs(1, only: RepositoryBackupNgJob, queue: :gitbackups_perform) do
      GitHub.stubs(realtime_backups_enabled?: true)
      Repository.any_instance.stubs(:backup_queue).returns("backup_fs123")
      simple_push!
    end

    enqueued_job = enqueued_jobs.find { |j| j[:job] == RepositoryBackupNgJob }
    enqueued_args = enqueued_job["arguments"]
    assert_equal @repo.id, enqueued_args[0]
    assert_equal "repository", enqueued_args[1]["value"]
    assert_in_delta Time.now, enqueued_args[2]["pushed_at"]["value"].to_time, 5.seconds
  end

  test "updates network push stats" do
    network = @repo.network
    assert_equal 0, network.pushed_count
    assert_equal 0, network.pushed_count_since_maintenance
    assert_nil network.pushed_at
    updated_at = network.updated_at

    Timecop.travel(DateTime.now + 10.seconds) do
      simple_push!
    end

    network.reload
    assert_equal 1, network.pushed_count
    assert_equal 1, network.pushed_count_since_maintenance
    refute_nil network.pushed_at
    assert network.updated_at > updated_at + 5.seconds
  end

  test "updates disk usage stats" do
    RepositoryDiskUsageJob.expects(:enqueue_once_per_interval).with(args: [@repo.id], interval: 60 * 60)
    simple_push!
  end

  test "sets the default branch on first push" do
    # This is the state of a brand new repository: on-disk it points to master
    # and in the DB the column is NULL
    assert_equal "refs/heads/master", @repo.get_default_branch
    assert_nil @repo.read_attribute(:master_branch)

    # Create the reference without going through the code that would try to
    # update the default branch. This simulates a push from the user
    commit_data = {
      message: "a commit",
      committer: @pusher,
    }
    commit = @repo.commits.create(commit_data) do |stage|
      stage.add("a-file", "a-content")
    end
    RefUpdater.update_ref(@repo, "refs/heads/new-default", commit.oid)

    refs = [["refs/heads/new-default", "0" * 40, commit.oid]]
    perform_push_job([@repo.path, @pusher.login, refs, Time.current])
    @repo.reload

    assert_nil @repo.read_attribute(:master_branch)
    assert_equal "new-default", @repo.default_branch
    assert_equal "refs/heads/new-default", @repo.get_default_branch
  end

  test "correctly sets the actor for the audit log" do
    events = subscribe "repo.update_default_branch"

    commit_data = {
      message: "a commit",
      committer: @pusher,
    }
    commit = @repo.commits.create(commit_data) do |stage|
      stage.add("a-file", "a-content")
    end
    RefUpdater.update_ref(@repo, "refs/heads/new-default", commit.oid)

    refs = [["refs/heads/new-default", "0" * 40, commit.oid]]
    perform_push_job([@repo.path, @pusher.login, refs, Time.current])

    # tests for auditing change
    assert event = events.pop
    assert_equal @pusher.login, event.payload[:actor]
  end

  test "keeps the branch to master if it's pushed along others" do
    # This is the state of a brand new repository: on-disk it points to master
    # and in the DB the column is NULL
    assert_equal "refs/heads/master", @repo.get_default_branch
    assert_nil @repo.read_attribute(:master_branch)

    # Create the reference without going through the code that would try to
    # update the default branch. This simulates a push from the user
    commit_data = {
      message: "a commit",
      committer: @pusher,
    }
    commit = @repo.commits.create(commit_data) do |stage|
      stage.add("a-file", "a-content")
    end
    RefUpdater.update_ref(@repo, "refs/heads/acme-default", commit.oid)
    RefUpdater.update_ref(@repo, "refs/heads/master", commit.oid)

    refs = [["refs/heads/acme-default", "0" * 40, commit.oid],
            ["refs/heads/master", "0" * 40, commit.oid]]
    perform_push_job([@repo.path, @pusher.login, refs, Time.current])
    @repo.reload

    assert_nil @repo.read_attribute(:master_branch)
    assert_equal "master", @repo.default_branch
    assert_equal "refs/heads/master", @repo.get_default_branch
  end

  test "updates default branch even if a tag with the same short name exists" do
    assert_equal "refs/heads/master", @repo.get_default_branch
    assert_equal [], @repo.refs.names

    # Create the reference without going through the code that would try to
    # update the default branch. This simulates a push from the user
    commit_data = {
      message: "a commit",
      committer: @pusher,
    }
    commit = @repo.commits.create(commit_data) do |stage|
      stage.add("a-file", "a-content")
    end
    RefUpdater.update_ref(@repo, "refs/heads/acme-default", commit.oid)
    RefUpdater.update_ref(@repo, "refs/tags/master", commit.oid)

    refs = [["refs/heads/acme-default", "0" * 40, commit.oid],
            ["refs/tags/master", "0" * 40, commit.oid]]
    perform_push_job([@repo.path, @pusher.login, refs, Time.current])

    @repo.reload

    assert_equal "refs/heads/acme-default", @repo.get_default_branch
  end

  def build_input(refs)
    refs.map { |(ref, bef, af)| "#{bef} #{af} #{ref}" }.join("\n")
  end

  context "retries" do
    test "raises error on Push validation failure" do
      push_args = [
        @repo.shard_path,
        "defunkt",
        @refs,
        Time.current
      ]

      Push.any_instance.stubs(:valid?).returns(false)

      assert_raises(ActiveRecord::RecordInvalid) do
        perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
          trigger_push_event(*push_args)
        end
      end
    end

    test "writes push on retry" do
      push_args = [
        @repo.shard_path,
        "defunkt",
        @refs,
        Time.current
      ]

      # A bit hacky, but simulate a couple failed saves this way.
      # This is stubbing valid? because we need to return a value at the end to stop raising and #returns needs a literal value.
      Push.any_instance.stubs(:valid?)
        .returns(true) # succeed in writing the first push
        .then.raises(ActiveRecord::ConnectionFailed) # fail in writing the next 2
        .then.raises(ActiveRecord::ConnectionFailed)
        .then.returns(true) # succeed thereafter

      assert_equal 0, Push.where(repository_id: @repo.id).count

      perform_push_job(push_args)

      assert_equal 4, Push.where(repository_id: @repo.id).count
    end

    test "retries on spokes connection error" do
      push_args = [@repo.shard_path, "defunkt", @refs, Time.current]
      Repository.any_instance.stubs(:adjust_default_branch).raises(SpokesAPI::TwirpConnectionError).then.returns(true)
      assert_nothing_raised { perform_push_job(push_args) }
    end
  end

  context "creating Push records" do
    context "pushing a new branch" do
      test "creates a Push record" do
        after = "251a4d8118d2c9c746c687efceaacac799e67ad9"
        ref = "refs/heads/master"
        push_test! @repo.shard_path, [
          GitHub::NULL_OID,
          after,
          ref].join(" ")

        assert push = @repo.pushes.last
        assert_equal GitHub::NULL_OID, push.before
        assert_equal after, push.after
        assert_equal "branch_creation", push.push_type
        assert_equal ref, push.ref
        assert_equal @repo, push.repository
        assert_equal @pusher, push.pusher
      end

      test "creates a Push record even if the branch has 'tags/' in the name" do
        after = "251a4d8118d2c9c746c687efceaacac799e67ad9"
        ref = "refs/heads/some/tags/are/cool"
        push_test! @repo.shard_path, [
          GitHub::NULL_OID,
          after,
          ref].join(" ")

        assert push = @repo.pushes.last
        assert_equal GitHub::NULL_OID, push.before
        assert_equal after, push.after
        assert_equal "branch_creation", push.push_type
        assert_equal ref, push.ref
        assert_equal @repo, push.repository
        assert_equal @pusher, push.pusher
      end
    end

    context "pushing commits" do
      test "creates a Push record" do
        example_repo :post_receive_job_test, @repo

        before = "c1800491d95c42b4e96fb83f31fe8d9230c62907"
        after = "63611721afd41f58f801d66e543d8288b4c5eb44"
        ref = "refs/heads/master"
        push_test!(@repo.shard_path, [
          before,
          after,
          ref].join(" "))

        assert push = @repo.pushes.last
        assert_equal before, push.before
        assert_equal after, push.after
        assert_equal "push", push.push_type
        assert_equal ref, push.ref
        assert_equal @repo, push.repository
        assert_equal @pusher, push.pusher
      end
    end

    context "pushing a branch deletion" do
      test "creates a Push record" do
        before = "251a4d8118d2c9c746c687efceaacac799e67ad9"
        ref = "refs/heads/master"
        push_test! @repo.shard_path, [
          before,
          GitHub::NULL_OID,
          ref].join(" ")

        assert push = @repo.pushes.last
        assert_equal before, push.before
        assert_equal GitHub::NULL_OID, push.after
        assert_equal "branch_deletion", push.push_type
        assert_equal ref, push.ref
        assert_equal @repo, push.repository
        assert_equal @pusher, push.pusher
      end
    end

    context "force pushing a branch" do
      test "creates a Push record" do
        before = "c1800491d95c42b4e96fb83f31fe8d9230c62907"
        after = "63611721afd41f58f801d66e543d8288b4c5eb44"
        ref = "refs/heads/master"
        push_test!(@repo.shard_path, [
          before,
          after,
          ref].join(" "))

        assert push = @repo.pushes.last
        assert_equal before, push.before
        assert_equal after, push.after
        assert_equal "force_push", push.push_type
        assert_equal ref, push.ref
        assert_equal @repo, push.repository
        assert_equal @pusher, push.pusher
      end
    end

    context "merging a PR" do
      test "creates a Push record with push_type" do
        repo = create(:repository, owner: @user, from_example: :mojombo_grit)
        pr = create(:pull_request,
                      repository: repo,
                      user: @user,
                      head_ref: "lazy_delegator")

        perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
          pr.merge
        end

        assert push = repo.pushes.last
        assert_equal pr.base_sha, push.before
        assert_equal pr.merge_commit_sha, push.after
        assert_equal pr.user, push.pusher
        assert_equal "refs/heads/#{pr.base_ref}", push.ref
        assert_equal "pr_merge", push.push_type
      end
    end

    test "creates a merge queue Push record" do
      repo = create(:repository, owner: @user, from_example: :post_receive_job_test)

      before = "c1800491d95c42b4e96fb83f31fe8d9230c62907"
      after = "63611721afd41f58f801d66e543d8288b4c5eb44"
      ref = "refs/heads/master"
      push_test! repo.shard_path, [
        before,
        after,
        ref].join(" "),
        merge_action: :merge_queue_merge

      assert push = repo.pushes.last
      assert_equal before, push.before
      assert_equal after, push.after
      assert_equal "merge_queue_merge", push.push_type
      assert_equal ref, push.ref
      assert_equal repo, push.repository
      assert_equal @pusher, push.pusher
    end

    test "creates a merge queue Push record for api operation" do
      repo = create(:repository, owner: @user, from_example: :post_receive_job_test)

      before = "c1800491d95c42b4e96fb83f31fe8d9230c62907"
      after = "63611721afd41f58f801d66e543d8288b4c5eb44"
      ref = "refs/heads/master"
      push_test! repo.shard_path, [
        before,
        after,
        ref].join(" "),
        merge_action: :api_merge_queue_merge

      assert push = repo.pushes.last
      assert_equal before, push.before
      assert_equal after, push.after
      assert_equal "merge_queue_merge", push.push_type
      assert_equal ref, push.ref
      assert_equal repo, push.repository
      assert_equal @pusher, push.pusher
    end

    test "doesn't write Push records for merge queue refs" do
      before = "251a4d8118d2c9c746c687efceaacac799e67ad9"
      ref = "refs/gh/queue/master/pr-foo"
      push_test! @repo.shard_path, [
        before,
        GitHub::NULL_OID,
        ref].join(" ")

      assert_equal 0, @repo.pushes.count
    end
  end

  context "filter 0 commit pushes" do
    test "does not write push records for pushes with matching before/after SHA" do
      Timecop.freeze do
        # Two valid ref updates, and two no-op ref updates
        refs = [
          ["refs/heads/master", "4c8124ffcf4039d292442eeccabdeca5af5c5017", "a47fd41f3aa4610ea527dcc1669dfdb9c15c5425"],
          ["refs/heads/dead", "12521512512515325h4234v3c322323423423423", GitHub::NULL_OID],
          ["refs/heads/awesome", "5dea2f86730665894cf03f2b1fac98c1217a9fb4", "5dea2f86730665894cf03f2b1fac98c1217a9fb4"],
          ["refs/heads/lame", GitHub::NULL_OID, GitHub::NULL_OID]
        ]

        assert_equal 0, Push.where(repository_id: @repo.id).count

        perform_push_job([@repo.shard_path, "defunkt", refs, Time.now])

        assert_equal 2, Push.where(repository_id: @repo.id).count
      end
    end

    test "No-op when refs do not contain ref updates" do
      Timecop.freeze do
        # Two valid ref updates, and two no-op ref updates
        refs = [
          ["refs/heads/awesome", "5dea2f86730665894cf03f2b1fac98c1217a9fb4", "5dea2f86730665894cf03f2b1fac98c1217a9fb4"],
          ["refs/heads/lame", GitHub::NULL_OID, GitHub::NULL_OID]
        ]

        push_args = [@repo.shard_path, "defunkt", refs, Time.now]

        assert_equal 0, Push.where(repository_id: @repo.id).count

        perform_push_job(push_args)

        assert_equal 0, Push.where(repository_id: @repo.id).count
      end
    end
  end

  context "with nil pusher" do
    test "writes push records with User.ghost" do
      perform_push_job([
        @repo.shard_path,
        nil, # user login
        @refs,
        Time.current
      ])

      assert_equal 4, Push.where(repository_id: @repo.id).count
      Push.where(repository_id: @repo.id).each do |push|
        assert_equal User.ghost, push.pusher
      end
    end
  end

  test "ref_updates are still processed when GitRPC::ObjectMissing is rescued" do
    example_repo :post_receive_job_test, @repo
    commit_object = @repo.commits.find(@repo.ref_to_sha(@repo.default_branch))
    Repositories::RefUpdate.any_instance.stubs(:commits_pushed).raises(GitRPC::ObjectMissing).then.returns([commit_object])

    assert_equal 0, Push.where(repository_id: @repo.id).count

    perform_push_job([@repo.path, @pusher.login, @refs, Time.current])

    assert_equal @refs.count - 1, Push.where(repository_id: @repo.id).count
    assert_dogstats_increment 1, "repository_push.ref_update_object_missing"
  end
end
