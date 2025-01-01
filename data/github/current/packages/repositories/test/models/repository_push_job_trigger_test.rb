# typed: false
# frozen_string_literal: true

require "test_helper"

class RepositoryPushJobTriggerTest < GitHub::TestCase
  include DogstatsTestHelpers
  include HydroMessageJobTestHelpers
  include HydroTestHelpers

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user   = create(:user)
    @pusher = create(:user)

    @repository = create(:repository, owner: @user, from_example: :post_receive_job_test)
    @repository.analyze_languages

    @public_gist = GistHelpers.generate(
      user: @user,
      contents: [{
        name: "some_file.rb",
        value: "some content",
      }],
      description: "my cool gist",
    )

    @branch = "master"
    @ref = "refs/heads/#{@branch}"
    @before = "c1800491d95c42b4e96fb83f31fe8d9230c62907"
    @after = "63611721afd41f58f801d66e543d8288b4c5eb44"
    @updates = [Git::Ref::Update.new(repository: @repository, refname: @ref, before_oid: @before, after_oid: @after)]
    @time = Time.current
    @expected_ref_args = [[@ref, @before, @after]]

    @trigger = RepositoryPushJobTrigger.new(@repository, @pusher.login, @updates, @time)
  end

  setup do
    # Override for All-Features
    GitHub.flipper[:aleph_language_ruby].enable
    GitHub.flipper[:aleph_darkship_language_ruby].disable

    @enabled_hydro_flags = TestEnv.test_all_features? ? Repositories::HydroPushJobFlags::FLAGS : []

    SecretScanning::Instrumentation::RepositoryServiceFlags.any_instance.stubs(:post_receive_service_flags).returns([])
    @hydro_message = {
      repository: Hydro::EntitySerializer.repository(@repository),
      actor: Hydro::EntitySerializer.user(@pusher),
      owner: Hydro::EntitySerializer.user(@user),
      ref_updates: [{ ref_name: @ref, previous_ref_oid: @before, current_ref_oid: @after }],
      feature_flags: [],
      request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
      pushed_at: @trigger.pushed_at,
      business_id: nil,
      business: {
        id: nil,
        name: "",
      },
      languages: %w[Ruby Go],
    }
  end

  test "update is not handled by Secret Scanning for a Gist" do
    SecretScanning::Instrumentation::RepositoryPushHandler.expects(:on_repository_push).never

    updates = [Git::Ref::Update.new(repository: @public_gist, refname: @ref, before_oid: @before, after_oid: @after)]
    trigger = RepositoryPushJobTrigger.new(@public_gist, @pusher.login, updates, Time.current)
    trigger.enqueue
  end

  test "update is not handled by Secret Scanning for a Wiki" do
    SecretScanning::Instrumentation::RepositoryPushHandler.expects(:on_repository_push).never
    wiki = @repository.unsullied_wiki
    updates = [Git::Ref::Update.new(repository: wiki, refname: @ref, before_oid: @before, after_oid: @after)]
    trigger = RepositoryPushJobTrigger.new(wiki, @pusher.login, updates, Time.current)
    trigger.enqueue
  end

  context "filter 0 commit pushes" do
    test "only enqueues with valid ref updates" do
      # Two valid ref updates, and two no-op ref updates
      updates = [
        Git::Ref::Update.new(repository: @repository, refname: @ref, before_oid: @before, after_oid: @after),
        Git::Ref::Update.new(repository: @repository, refname: "refs/heads/dead", before_oid: "12521512512515325a4234a3c322323423423423", after_oid: GitHub::NULL_OID),
        Git::Ref::Update.new(repository: @repository, refname: "refs/heads/awesome", before_oid: "5dea2f86730665894cf03f2b1fac98c1217a9fb4", after_oid: "5dea2f86730665894cf03f2b1fac98c1217a9fb4"),
        Git::Ref::Update.new(repository: @repository, refname: "refs/heads/lame", before_oid: GitHub::NULL_OID, after_oid: GitHub::NULL_OID),
      ]
      with_hydro_publisher(GitHub.sync_hydro_publisher) do
        trigger = RepositoryPushJobTrigger.new(@repository, @pusher.login, updates, @time)
        trigger.enqueue
        expected_refs = [
          [@ref, @before, @after],
          ["refs/heads/dead", "12521512512515325a4234a3c322323423423423", GitHub::NULL_OID],
        ]

        assert_hydro_published_partial(
            { path: @repository.shard_path, pusher: @pusher.login, pushed_at: @time, ref_updates: expected_refs.map { |ref, before, after| { ref: ref, before: before, after: after } } },
            schema: "github.repositories.v1.Pushed",
            partition_key: @repository.id
          )
      end
    end

    test "Does not enqueue with no ref updates" do
      updates = [
        Git::Ref::Update.new(repository: @repository, refname: "refs/heads/awesome", before_oid: "5dea2f86730665894cf03f2b1fac98c1217a9fb4", after_oid: "5dea2f86730665894cf03f2b1fac98c1217a9fb4"),
        Git::Ref::Update.new(repository: @repository, refname: "refs/heads/lame", before_oid: GitHub::NULL_OID, after_oid: GitHub::NULL_OID),
      ]
      trigger = RepositoryPushJobTrigger.new(@repository, @pusher.login, updates, @time)
      trigger.enqueue
      refute_hydro_messages(schema: "github.repositories.v1.Pushed")
    end
  end
  context "sockstat context" do
    context "oauth_access_id" do
      test "when passed as part of the sockstat hash" do
        trigger = RepositoryPushJobTrigger.new(@repository, @pusher.login, @updates, @time, nil, { oauth_access_id: 42 })
        with_hydro_publisher(GitHub.sync_hydro_publisher) do
          trigger.enqueue


          assert_hydro_published_partial(
            { pusher: @pusher.login, oauth_access_id: 42 },
            schema: "github.repositories.v1.Pushed",
            partition_key: @repository.id
          )

        end
      end

      test "when User#oauth_access returns a record" do
        access = create(:oauth_access)
        @pusher.oauth_access = access

        with_hydro_publisher(GitHub.sync_hydro_publisher) do
          trigger = RepositoryPushJobTrigger.new(@repository, @pusher, @updates, @time)
          trigger.enqueue

          assert_hydro_published_partial(
            { pusher: @pusher.login, oauth_access_id: access.id },
            schema: "github.repositories.v1.Pushed",
              partition_key: @repository.id
            )


        end
      end
    end

    context "installation" do
      test "when passed as part of the sockstat hash" do
        installation = make_integration_installation(target: @pusher, permissions: { "metadata" => :read })
        bot = installation.bot
        with_hydro_publisher(GitHub.sync_hydro_publisher) do
          trigger = RepositoryPushJobTrigger.new(@repository, bot.login, @updates, @time, nil, {
            installation_id: installation.ability_id, installation_type: installation.ability_type
          })

          trigger.enqueue
          assert_hydro_published_partial(
            { pusher: bot.display_login, installation_id: installation.ability_id, installation_type: installation.ability_type },
            schema: "github.repositories.v1.Pushed",
            partition_key: @repository.id
          )

        end
      end

      test "when a Bot with a hydrated installation is passed" do
        installation = make_integration_installation(target: @pusher, permissions: { "metadata" => :read })
        bot = installation.bot
        refute_nil bot.installation

        with_hydro_publisher(GitHub.sync_hydro_publisher) do
          trigger = RepositoryPushJobTrigger.new(@repository, bot, @updates, @time, nil)
          trigger.enqueue
          assert_hydro_published_partial(
            { pusher: bot.display_login, installation_id: installation.id, installation_type: installation.class.name,  },
            schema: "github.repositories.v1.Pushed",
            partition_key: @repository.id
          )

        end
      end
    end

    context "pat v2" do
      test "when passed as part of the sockstat hash" do
        with_hydro_publisher(GitHub.sync_hydro_publisher) do
          trigger = RepositoryPushJobTrigger.new(@repository, @pusher.login, @updates, @time, nil, { user_programmatic_access_id: 42 })
          trigger.enqueue


          assert_hydro_published_partial(
            { pusher: @pusher.login, user_programmatic_access_id: 42 },
            schema: "github.repositories.v1.Pushed",
            partition_key: @repository.id
          )


        end

      end

      test "when a User#programmatic_access returns a record" do
        access = create(:user_programmatic_access, owner: @pusher)
        @pusher.programmatic_access = access

        with_hydro_publisher(GitHub.sync_hydro_publisher) do
          trigger = RepositoryPushJobTrigger.new(@repository, @pusher, @updates, @time, nil)
          trigger.enqueue

          assert_hydro_published_partial(
            { pusher: @pusher.login, user_programmatic_access_id: access.id },
              schema: "github.repositories.v1.Pushed",
              partition_key: @repository.id
            )



        end

      end
    end
  end

  context "push hydro event"  do
    test "enqueues RepositoryUpdateTechProjectAndStackJob job" do
      trigger = RepositoryPushJobTrigger.new(@repository, @pusher, @updates, @time, nil)

      perform_enqueued_hydro_jobs(publisher: GitHub.sync_hydro_publisher, only: [HydroAnalyzeTechProjectStackOnPushJob], allowed_primary_query_count: 0) do
        trigger.enqueue
      end
      assert_enqueued_jobs 1, only: RepositoryUpdateTechProjectAndStackJob, queue: :tech_project_stack
    end

    test "publishes repository pushed event" do
      GitHub.context.push(actor_ip: "1.1.1.1") # add this for request_context
      trigger = RepositoryPushJobTrigger.new(
        @repository,
        @pusher.login,
        @updates,
        @time,
        ["pull.ready"],
        { "oauth_access_id": 1, "user_programmatic_access_id": 2, "installation_id": 3, "installation_type": "IntegrationInstallation" },
        excluded_pull_ids: [1],
        merge_method: :merge,
        merge_action: :merge_queue,
      )

      with_hydro_publisher(GitHub.sync_hydro_publisher) do
        trigger.enqueue

        hydro_payload = {
          repository_id: @repository.id,
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          ref_updates: @updates.map { |u| { ref: u.refname, before: u.before_oid, after: u.after_oid } },
          pushed_at: @time,
          push_options: Hydro::EntitySerializer.push_options(["pull.ready"]),
          oauth_access_id: 1,
          user_programmatic_access_id: 2,
          installation_id: 3,
          installation_type: "IntegrationInstallation",
          excluded_pull_ids: [1],
          merge_method: "merge",
          merge_action: "merge_queue",
          pusher: @pusher.login,
          enabled_flags: @enabled_hydro_flags,
          path: @repository.shard_path,
          total_ref_count: 1,
          ref_batch_number: 1
        }

        hydro_payload[:total_branch_count] = 1
        assert_hydro_published(
          hydro_payload,
          schema: "github.repositories.v1.Pushed",
          partition_key: @repository.id)

        full_message = GitHub.sync_hydro_publisher.sink.messages.find { |m| m.schema == "github.repositories.v1.Pushed" }
        assert_equal "{}", full_message.headers["replication_state"]
      end
    end

    test "publishes repository pushed event for wiki" do
      time = Time.current
      wiki = @repository.unsullied_wiki

      trigger = RepositoryPushJobTrigger.new(
        wiki,
        @pusher.login,
        @updates,
        time,
      )

      with_hydro_publisher(GitHub.sync_hydro_publisher) do
        trigger.enqueue

        assert_hydro_published(
          {
            repository_id: @repository.id,
            request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
            ref_updates: @updates.map { |u| { ref: u.refname, before: u.before_oid, after: u.after_oid } },
            pushed_at: time,
            pusher: @pusher.login,
            enabled_flags: @enabled_hydro_flags,
            path: wiki.shard_path,
            total_ref_count: 1,
            ref_batch_number: 1,
            total_branch_count: 1
          },
          schema: "github.repositories.v1.Pushed",
          partition_key: @repository.id,
        )

        full_message = GitHub.sync_hydro_publisher.sink.messages.find { |m| m.schema == "github.repositories.v1.Pushed" }
        assert_equal "{}", full_message.headers["replication_state"]
      end
    end

    test "publishes event without ref updates" do
      GitHub.flipper[:gitauth_publish_push_event].enable
      with_hydro_publisher(GitHub.sync_hydro_publisher) do
        RepositoryPushJobTrigger.new(@repository, @pusher.login, [], @time).enqueue
        assert_hydro_published(
          {
            repository_id: @repository.id,
            request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
            ref_updates: [],
            pushed_at: @time,
            pusher: @pusher.login,
            enabled_flags: @enabled_hydro_flags,
            path: @repository.shard_path,
            total_ref_count: 0,
            ref_batch_number: 1,
            total_branch_count: 0
          },
          schema: "github.repositories.v1.Pushed",
          partition_key: @repository.id,
        )
      end
    end

    context "with spokes api fail fast" do
      test "handles spokes api failure" do
        updates = [
          Git::Ref::Update.new(repository: @repository, refname: @ref, before_oid: @before, after_oid: @after),
          Git::Ref::Update.new(repository: @repository, refname: "refs/heads/dead", before_oid: "18aeae1b92522673ad685f7ae04eddae2a3310c1", after_oid: GitHub::NULL_OID),
          Git::Ref::Update.new(repository: @repository, refname: "refs/heads/awesome", before_oid: "23aa477eaf0d96de1076d38a14e1ad5b05083ade", after_oid: "451a4d8118d2c9c746c687efceaacac799e67ad9"),
          Git::Ref::Update.new(repository: @repository, refname: "refs/heads/lame", before_oid: GitHub::NULL_OID, after_oid: "a9f104bd1f0cdb01e3a7a53415128f330e0e24be")
        ]

        assert_equal 0, Push.where(repository_id: @repository.id).count

        SpokesAPI::Client.any_instance.stubs(:compare_oids).raises(SpokesAPI::Error.from_twirp_error(Twirp::Error.resource_exhausted("testing"))).then.returns([])

        trigger = RepositoryPushJobTrigger.new(@repository, @pusher, updates, Time.now, nil)

        perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
          trigger.enqueue
        end

        assert_dogstats_increment "push.get_changed_files_spokes_api.error", tags: ["error:SpokesAPI::ResourceExhausted"]
        assert_equal 4, Push.where(repository_id: @repository.id).count
      end
    end
  end

  test "splits up push events with too many ref updates" do
    updates = 2040.times.map do |t| # should make 3 events with 1k, 1k, and 40 ref updates
      Git::Ref::Update.new(repository: @repository, refname: "refs/heads/branch_#{t}", before_oid: @before, after_oid: @after)
    end

    updates << Git::Ref::Update.new(repository: @repository, refname: "refs/tags/tag_1", before_oid: @before, after_oid: @after)

    expected_update_args = 2040.times.map do |t|
      { ref: "refs/heads/branch_#{t}", before: @before, after: @after }
    end

    expected_update_args << { ref: "refs/tags/tag_1", before: @before, after: @after }

    trigger = RepositoryPushJobTrigger.new(
      @repository,
      @pusher.login,
      updates,
      @time,
      ["pull.ready"],
      { "oauth_access_id": 1, "user_programmatic_access_id": 2, "installation_id": 3, "installation_type": "IntegrationInstallation" },
    excluded_pull_ids: [1],
    merge_method: :merge,
    merge_action: :merge_queue,
  )
    with_hydro_publisher(GitHub.sync_hydro_publisher) do
      trigger.enqueue

      hydro_payload = {
        repository_id: @repository.id,
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        ref_updates: [],
        pushed_at: @time,
        push_options: Hydro::EntitySerializer.push_options(["pull.ready"]),
        oauth_access_id: 1,
        user_programmatic_access_id: 2,
        installation_id: 3,
        installation_type: "IntegrationInstallation",
        excluded_pull_ids: [1],
        merge_method: "merge",
        merge_action: "merge_queue",
        pusher: @pusher.login,
        enabled_flags: @enabled_hydro_flags,
        path: @repository.shard_path,
        total_ref_count: 2041,
        ref_batch_number: 1,
        total_branch_count: 2040
      }

      assert_hydro_published(
        hydro_payload.merge(ref_updates: expected_update_args[0..999]),
        schema: "github.repositories.v1.Pushed",
        partition_key: @repository.id
      )

      assert_hydro_published(
        hydro_payload.merge({ ref_updates: expected_update_args[1000..1999], ref_batch_number: 2 }),
        schema: "github.repositories.v1.Pushed",
        partition_key: @repository.id
      )

      assert_hydro_published(
        hydro_payload.merge({ ref_updates: expected_update_args[2000..2041], ref_batch_number: 3 }),
        schema: "github.repositories.v1.Pushed",
        partition_key: @repository.id
      )
    end
  end

  context "setting replication_state"  do
    test "does not override replication state if already populated" do
      last_writes = { my_cluster1: { gtid: "something1", time: 1 } }
      DatabaseSelector::ReplicationState.any_instance.expects(:to_hash).returns(last_writes)
      with_hydro_publisher(GitHub.sync_hydro_publisher) do
        RepositoryPushJobTrigger.new(@repository, @pusher.login, @updates, @time).enqueue
      end

      full_message = GitHub.sync_hydro_publisher.sink.messages.find { |m| m.schema == "github.repositories.v1.Pushed" }
      assert_equal last_writes.to_json, full_message.headers["replication_state"]
    end
  end
end
