# typed: true
# frozen_string_literal: true

require "test_helper"

class TransferRepositoryOrchestrationTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include HydroTestHelpers
  include DogstatsTestHelpers
  include CustomPropertiesTestHelper

  fixtures do
    @member_one = create(:user)
    @owner = create(:user)
    @org_one = create(:organization, admin: @owner)
    @team_one = create(:team, organization: @org_one)
    @repo = create(:private_repository, owner: @org_one)
    @team_one.add_member(@member_one, adder: @owner)
    @team_one.add_repository(@repo, :push)

    @member_two = create(:user)
    @org_two = create(:organization, admin: @member_two)
    @team_two = create(:team, organization: @org_two)
    @team_two.add_member(@member_two)

    @mock_counts_result = Struct.new(:data) do
      def data
        { "data" => { "count" => 0 } }
      end
    end

    @orgs_admin = create(:user)
    @org_one.add_admin(@orgs_admin)
    @org_two.add_admin(@orgs_admin)
  end

  setup do
    # Override for All-Features
    disable_feature_flag(:repo_transfer_owner_lock)
  end

  test "passing team_ids as an Array" do
    assert_equal @repo.owner, @org_one

    RepositoryOrchestration.transfer(@repo, actor_id: @owner.id, new_owner_id: @member_two.id).execute(synchronous: true)

    @repo.reload

    assert_equal @repo.owner, @member_two
  end

  test "passing options works" do
    assert_equal @repo.owner, @org_one

    RepositoryOrchestration.transfer(@repo, actor_id: @owner.id, new_owner_id: @member_two.id, notify_target: true).execute(synchronous: true)

    @repo.reload

    assert_equal @repo.owner, @member_two
  end

  test "successful transfer job retires the original repo namespace when it should be retired" do
    refute RetiredNamespace.for(owner: @org_one.display_login, name: @repo.name)

    RetiredNamespace.expects(:should_retire?).with(@repo, rescue_kv: true).returns(true)

    RepositoryOrchestration.transfer(@repo, actor_id: @owner.id, new_owner_id: @member_two.id).execute!(synchronous: true)

    assert RetiredNamespace.for(owner: @org_one.display_login, name: @repo.name)
  end

  test "successful transfer job does not retire the original repo namespace when it should not be retired" do
    refute RetiredNamespace.for(owner: @org_one.display_login, name: @repo.name)

    RetiredNamespace.expects(:should_retire?).with(@repo, rescue_kv: true).returns(false)

    RepositoryOrchestration.transfer(@repo, actor_id: @owner.id, new_owner_id: @member_two.id).execute!(synchronous: true)

    refute RetiredNamespace.for(owner: @org_one.display_login, name: @repo.name)
  end

  test "successful transfer deletes the shadowed redirect" do
    user = create(:user)
    repo = create(:repository, owner: user, name: "repo")

    previous_login = user.login

    disable_feature_flag(:packages_namespace_retirement)
    RetiredNamespace.stubs(:should_retire?).with(repo).returns(false)
    user.rename!("new-login")

    user.reload

    assert_equal "new-login", user.login
    assert RepositoryRedirect.exists?(repository_name: "#{previous_login}/repo")

    User.any_instance.stubs(:login_reserved_with_reason?).returns({})
    new_user = create(:user, login: previous_login)
    new_repo = create(:repository, name: "repo")

    RetiredNamespace.stubs(:should_retire?).with(new_repo, rescue_kv: true).returns(false)

    orchestration = RepositoryOrchestration.transfer(
      new_repo,
      actor_id: new_repo.owner.id,
      new_owner_id: new_user.id
    )

    orchestration.execute!(synchronous: true)

    assert orchestration.succeeded?

    refute RepositoryRedirect.exists?(repository_name: "#{previous_login}/repo")
  end

  test "successful transfer job retires the original repo namespace when KV unavailable", skip_with_all_emus: true, skip_enterprise: true do
    repo = create(:repository)
    owner_login = repo.owner_login

    refute RetiredNamespace.for(owner: owner_login, name: repo.name)

    Actions::RepositoryUsage.stubs(:uses_in_the_past_week).raises(GitHub::KV::UnavailableError.new)

    GitHub.pond_client.stubs(:counts).returns(@mock_counts_result.new)

    RepositoryOrchestration.transfer(repo, actor_id: repo.owner.id, new_owner_id: @member_two.id).execute!(synchronous: true)

    assert RetiredNamespace.for(owner: owner_login, name: repo.name)
  end

  test "failed transfer rolls back changes" do
    example_repo(:simple, @repo)
    @repo.create_repository_auth_version(version: 42)

    # Mock a failure during the auth_version increment, after the version is updated in the DB
    @repo.stubs(:reset_repository_auth_version).raises(StandardError.new("boom"))

    assert_equal @org_one, @repo.owner
    assert_equal @org_one, @repo.network_owner

    o = RepositoryOrchestration.transfer(@repo, actor_id: @owner.id, new_owner_id: @member_two.id)
    assert_raises StandardError do
      o.execute(synchronous: true)
    end

    o.reload
    assert_equal 1, o.attempts
    assert_equal "failed", o.state
    assert_equal "boom", o.error_message
    assert_equal "update_owner", o.step_name

    @repo.reload
    assert_equal @org_one, @repo.owner
    assert_equal @org_one, @repo.network_owner
    assert_equal 42, @repo.auth_version
  end

  test "successful transfer job results in repo ownership changed event for search indexing", skip_enterprise: true do
    example_repo(:simple, @repo)
    @repo.create_repository_auth_version(version: 42)

    assert_equal @repo.owner, @org_one

    orchestration = RepositoryOrchestration.transfer(@repo, actor_id: @owner.id, new_owner_id: @member_two.id)
    orchestration.class.stop_after_step = :instrument_transfer
    orchestration.execute(synchronous: true)

    repository_entity_serialized = Hydro::EntitySerializer.repository(@repo.reload)

    orchestration.class.stop_after_step = nil
    orchestration.execute(synchronous: true)

    @repo.reload
    assert_equal @repo.owner, @member_two

    assert_hydro_published({
      change: :OWNER_CHANGED,
      repository: repository_entity_serialized,
      ref: "refs/heads/#{@repo.default_branch}",
      owner_name: @member_two.name,
      old_owner_id: @org_one.id,
      auth_version: 43,
    }, schema: "github.search.v0.RepositoryChanged", ignore_extra_keys: true)

    assert_hydro_messages(count: 1, schema: "github.search.v0.RepositoryChanged")
  end

  test "increments the repository_auth_version", skip_enterprise: true do
    example_repo(:simple, @repo)
    @repo.create_repository_auth_version(version: 42)

    # Freeze time so the hydro event timestamps match
    Timecop.freeze do
      RepositoryOrchestration.transfer(@repo, actor_id: @owner.id, new_owner_id: @member_two.id).execute(synchronous: true)
      @repo.reload

      assert_equal 43, @repo.auth_version

      assert_hydro_published({
        change: :OWNER_CHANGED,
        repository: Hydro::EntitySerializer.repository(@repo),
        owner_name: @member_two.name,
        old_owner_id: @org_one.id,
        auth_version: 43,
      }, schema: "github.search.v0.RepositoryChanged", ignore_extra_keys: true)

      assert_hydro_messages(count: 1, schema: "github.search.v0.RepositoryChanged")
    end
  end

  test "passing non empty team_ids as an Array works, repo associated correctly" do
    assert_equal @repo.owner, @org_one
    target_team_ids = Array(@team_two.id)

    RepositoryOrchestration.transfer(@repo, actor_id: @owner.id, new_owner_id: @org_two.id, team_ids: target_team_ids).execute(synchronous: true)

    @repo.reload

    assert_equal @repo.teams, [@team_two]
  end

  test "passing non empty team_ids as an Array with extra options works" do
    assert_equal @repo.owner, @org_one
    target_team_ids = Array(@team_two.id)

    TransferRepositoryJob.perform_now(@repo.id, @owner.id, @org_two.id, target_team_ids, "notify_target" => true)

    @repo.reload

    assert_equal @repo.teams, [@team_two]
  end

  test "passing notify_target: true option causes an email to be sent" do
    AccountMailer
        .expects(:immediate_repository_transfer)
        .with(@repo, @owner, @org_two, @repo.nwo)
        .returns(stub(deliver_now: nil))

    RepositoryOrchestration.transfer(@repo, actor_id: @owner.id, new_owner_id: @org_two.id, notify_target: true).execute(synchronous: true)
  end

  test "fires installation repositories added webhook when transfer is successful" do
    events = subscribe "integration_installation.repositories_added"
    @repo.update(created_by_user_id: @owner.id)

    new_owner = create(:user, login: "new-owner")
    installation = make_integration_installation(target: new_owner, permissions: { "metadata" => :read })

    assert_equal @repo.owner, @org_one

    RepositoryOrchestration.transfer(@repo, actor_id: @member_one.id, new_owner_id: new_owner.id).execute(synchronous: true)

    @repo.reload

    assert_equal @repo.owner, new_owner

    expected_payload = {}.tap do |payload|
      payload[:installation_id]          = installation.id
      payload[:application_client_id]    = installation.integration.key
      payload[:name]                     = installation.integration.name
      payload[:slug]                     = installation.integration.slug
      payload[:repository_selection]     = "all"

      payload[:actor]                    = @member_one.login
      payload[:actor_id]                 = @member_one.id
      payload[:repositories_added]       = [@repo.id]
      payload[:repositories_added_names] = [@repo.full_name]
      payload[:integration]              = installation.integration.name
      payload[:integration_id]           = installation.integration.id
      payload[:app]                      = installation.integration.name
      payload[:app_id]                   = installation.integration.id
      payload[:user]                     = new_owner.to_s
      payload[:user_id]                  = new_owner.id
      payload[:requester_id]             = nil
    end

    assert event = events.pop, "not instrumented"
    assert_equal expected_payload, event.payload
  end

  # The user contribution cache is only cleared directly via KV in single tenant enterprise environments
  if GitHub.single_tenant_enterprise?
    test "retries if kv is down" do
      GitHub::KV.any_instance.stubs(:del).raises(GitHub::KV::UnavailableError)

      o = RepositoryOrchestration.transfer(@repo, actor_id: @owner.id, new_owner_id: @member_two.id)
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        o.execute(synchronous: false)
      end

      assert_equal :failed, o.reload.state.to_sym
      assert_equal Orchestration::MAX_ATTEMPTS + 1, o.attempts
    end
  end

  test "transferring an org owned private network with forks syncs org_owned_private_networks_with_forks" do
    admin = create(:user)
    org = create(:organization, admin: admin)
    org.allow_private_repository_forking(actor: admin)
    other_org = create(:organization, admin: admin)
    other_org.allow_private_repository_forking(actor: admin)
    repo = create(:private_repository, owner: org)
    fork = create(:fork_repository, forker: admin, fork_repo: repo)

    assert OrgOwnedPrivateNetworkWithForks.where(network_id: repo.network_id, owner_id: org.id).exists?

    o = RepositoryOrchestration.transfer(repo, actor_id: admin.id, new_owner_id: other_org.id)
    assert_difference("::OrgOwnedPrivateNetworkWithForks.count", 0) do
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        o.execute
      end
    end

    assert OrgOwnedPrivateNetworkWithForks.where(network_id: repo.network_id, owner_id: other_org.id).exists?
  end

  context "set custom properties" do
    test "skips creating properties if new owner is not an org" do
      RepositoryOrchestration.transfer(
        @repo,
        actor_id: @owner.id,
        new_owner_id: @member_two.id,
        custom_properties: { "env" => "prod" },
      ).execute(synchronous: true)

      @repo.reload

      assert_equal @repo.owner, @member_two
      assert_equal CustomPropertyValue.for_target(@repo), []
    end

    [true, false].each do |synchronous|
      test "creates properties #{synchronous ? "synchronous" : "async"} for the new owner and remove for the old owner" do
        definition_one = create :custom_property_definition, source: @org_one, property_name: "env"
        definition_two = create :custom_property_definition, source: @org_two, property_name: "env"
        create :custom_property_value, definition: definition_one, target: @repo, value: "prod"

        assert_equal CustomPropertyValue.for_target(@repo).where(definition_id: definition_one.id).map { |p| [p.property_name, p.value] }, [%w[env prod]]
        assert_equal CustomPropertyValue.for_target(@repo).where(definition_id: definition_two.id), []

        orchestration = RepositoryOrchestration.transfer(
          @repo,
          actor_id: @orgs_admin.id,
          new_owner_id: @org_two.id,
          custom_properties: { "env" => "test" },
        )
        if synchronous
          orchestration.execute(synchronous: true)
        else
          perform_enqueued_jobs(only: [TransferRepositoryJob, RepositoryOrchestrationJob]) do
            orchestration.execute(synchronous: false)
          end
        end

        @repo.reload

        assert_equal @repo.owner, @org_two
        assert_equal CustomPropertyValue.for_target(@repo).where(definition_id: definition_one.id), []
        assert_equal CustomPropertyValue.for_target(@repo).where(definition_id: definition_two.id).map { |p| [p.property_name, p.value] }, [%w[env test]]
      end

      test "keeps enterprise properties #{synchronous ? "synchronous" : "async"} when transferred within same business" do
        enterprise_org_one = create :enterprise_linked_organization
        business = enterprise_org_one.business
        org_admin = enterprise_org_one.admin
        repo = create :repository, owner: enterprise_org_one

        enterprise_org_two = create :enterprise_linked_organization, business: business, admin: org_admin

        biz_definition_version = create :custom_property_definition, source: business, property_name: "biz_version"
        biz_definition_app_id = create :custom_property_definition, source: business, property_name: "app_id"

        org_definition_one = create :custom_property_definition, source: enterprise_org_one, property_name: "env"

        create :custom_property_value, definition: biz_definition_version, target: repo, value: "2.0.0"
        create :custom_property_value, definition: biz_definition_app_id, target: repo, value: "123-abc"

        create :custom_property_value, definition: org_definition_one, target: repo, value: "prod"

        assert_equal repo_properties(repo, :manual), { "biz_version" => "2.0.0", "env" => "prod", "app_id" => "123-abc" }

        orchestration = RepositoryOrchestration.transfer(
          repo,
          actor_id: org_admin.id,
          new_owner_id: enterprise_org_two.id,
          custom_properties: { "app_id" => "456-def" },
        )
        if synchronous
          orchestration.execute(synchronous: true)
        else
          perform_enqueued_jobs(only: [TransferRepositoryJob, RepositoryOrchestrationJob]) do
            orchestration.execute(synchronous: false)
          end
        end

        repo.reload

        assert_equal repo.owner, enterprise_org_two

        assert_equal repo_properties(repo, :manual), {
          # kept on transfer
          "biz_version" => "2.0.0",
          # set by user
          "app_id" => "456-def"
        }
      end
    end

    test "keeps properties for old owner if transfer fails" do
      definition_one = create :custom_property_definition, source: @org_one, property_name: "env"
      definition_two = create :custom_property_definition, source: @org_two, property_name: "env"
      create :custom_property_value, definition: definition_one, target: @repo, value: "prod"

      assert_equal CustomPropertyValue.for_target(@repo).where(definition_id: definition_one.id).map { |p| [p.property_name, p.value] }, [%w[env prod]]
      assert_equal CustomPropertyValue.for_target(@repo).where(definition_id: definition_two.id), []

      failed = RepositoryOrchestration.transfer(
        @repo,
        actor_id: @orgs_admin.id,
        new_owner_id: @org_two.id,
        custom_properties: { "unknown" => "value" },
      ).execute(synchronous: true)

      @repo.reload

      assert failed
      assert_equal @repo.owner, @org_one
      assert_equal CustomPropertyValue.for_target(@repo).where(definition_id: definition_one.id).map { |p| [p.property_name, p.value] }, [%w[env prod]]
      assert_equal CustomPropertyValue.for_target(@repo).where(definition_id: definition_two.id), []
    end

    test "fails to transfer a repo if properties schema is invalid" do
      failed = RepositoryOrchestration.transfer(
        @repo,
        actor_id: @orgs_admin.id,
        new_owner_id: @org_two.id,
        custom_properties: { "unknown" => "value" },
      ).execute(synchronous: true)

      assert failed
      assert_equal CustomPropertyValue.for_target(@repo), []
    end

    test "fails to transfer a repo if properties values are invalid" do
      create :custom_property_definition, source: @org_two, property_name: "env"

      failed = RepositoryOrchestration.transfer(
        @repo,
        actor_id: @orgs_admin.id,
        new_owner_id: @org_two.id,
        custom_properties: { "env" => "invalid\"value" },
      ).execute(synchronous: true)

      assert failed
      assert_equal CustomPropertyValue.for_target(@repo), []
    end

    test "fails to transfer a repo if new owner over limit" do
      create_list(:private_repository, 2, owner: @org_two)
      count = Repository.where(owner_id: @org_two.id).count
      limiter = RepositoryLimit.new(@org_two)
      limiter.override(soft: count - 1, hard: count)

      o = RepositoryOrchestration.transfer(
        @repo,
        actor_id: @orgs_admin.id,
        new_owner_id: @org_two.id,
      )
      o.execute(synchronous: true)

      if limiter.enabled?
        refute o.succeeded?
        assert @repo.reload.owner_id != @org_two.id
        assert_equal "Owner is over repository limit.", o.error_message
      else
        assert o.succeeded?
        assert @repo.reload.owner_id == @org_two.id
      end
    end

    test "sends hard limit email" do
      create_list(:private_repository, 2, owner: @org_two)
      count = Repository.where(owner: @org_two).count
      limiter = RepositoryLimit.new(@org_two)
      limiter.override(soft: count, hard: count + 1)
      ActionMailer::Base.deliveries.clear

      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        o = RepositoryOrchestration.transfer(
          @repo,
          actor_id: @orgs_admin.id,
          new_owner_id: @org_two.id,
        )
        o.execute(synchronous: true)
      end

      if limiter.enabled?
        assert_equal 1, ActionMailer::Base.deliveries.size
        assert_equal "Repository limit reached for #{@org_two.display_login}", ActionMailer::Base.deliveries.first.subject
      else
        assert_equal 0, ActionMailer::Base.deliveries.size
      end
    end

    test "sends soft limit email" do
      create_list(:private_repository, 2, owner: @org_two)
      count = Repository.where(owner: @org_two).count
      limiter = RepositoryLimit.new(@org_two)
      limiter.override(soft: count + 1, hard: count + 2)
      ActionMailer::Base.deliveries.clear

      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        o = RepositoryOrchestration.transfer(
          @repo,
          actor_id: @orgs_admin.id,
          new_owner_id: @org_two.id,
        )
        o.execute(synchronous: true)
      end

      if limiter.enabled?
        assert_equal 1, ActionMailer::Base.deliveries.size
        assert_equal "Approaching repository limit for #{@org_two.display_login}", ActionMailer::Base.deliveries.first.subject
      else
        assert_equal 0, ActionMailer::Base.deliveries.size
      end
    end

    test "fails to transfer a repo if user does not have permissions to set properties" do
      create :custom_property_definition, source: @org_two, property_name: "env"

      failed = RepositoryOrchestration.transfer(
        @repo,
        actor_id: @owner.id,
        new_owner_id: @org_two.id,
        custom_properties: { "env" => "prod" },
      ).execute(synchronous: true)

      assert failed
      assert_equal CustomPropertyValue.for_target(@repo), []
    end
  end

  test "locks are logged" do
    expected_log = {
      "code.namespace" => "TransferRepositoryOrchestration",
      "code.function" => "attempt_step",
      "Body" => /.*Unlocking repository excluding descendents.*/,
      "gh.repo.locked" => "true",
      "gh.repo.old_lock_reason" => "transferring_ownership",
    }.freeze

    assert_logged(**expected_log) do
      RepositoryOrchestration.transfer(@repo, actor_id: @owner.id, new_owner_id: @member_two.id, notify_target: true).execute(synchronous: true)
      assert_equal @repo.owner, @member_two
    end
  end

  test "unlocks repository even if it is locked for nil reason" do
    assert_equal @repo.owner, @org_one

    # Execute the sync phase of the orchestration, which locks the repo
    orchestration = RepositoryOrchestration.transfer(@repo, actor_id: @owner.id, new_owner_id: @member_two.id, notify_target: true)
    orchestration.execute

    # Simulate that lock_reason is set to nil
    assert @repo.reload.lock_reason
    @repo.lock_reason = nil
    @repo.save!

    # Now do the portion which unlocks the repo
    orchestration.execute(synchronous: true)

    assert_equal @repo.owner, @member_two
    refute @repo.locked?
    assert_dogstats_increment(1, "repository.transfer.unlocking_from_nil_lock_reason")
  end

  if GitHub.sponsors_enabled?
    test "enqueues jobs to update repo-sponsorables when old owner has a Sponsors listing" do
      create(:sponsors_listing, sponsorable: @org_one)

      assert_enqueued_with(
        job: UpdateOwnerRepositorySponsorablesJob,
        args: [{ sponsorable_id: @org_one.id }],
      ) do
        assert_enqueued_with(
          job: UpdateOwnerRepositorySponsorablesJob,
          args: [{ sponsorable_id: @member_two.id }],
        ) do
          RepositoryOrchestration.transfer(@repo, actor_id: @owner.id, new_owner_id: @member_two.id).execute(synchronous: true)
        end
      end
    end

    test "enqueues jobs to update repo-sponsorables when new owner has a Sponsors listing" do
      create(:sponsors_listing, sponsorable: @member_two)

      assert_enqueued_with(
        job: UpdateOwnerRepositorySponsorablesJob,
        args: [{ sponsorable_id: @org_one.id }],
      ) do
        assert_enqueued_with(
          job: UpdateOwnerRepositorySponsorablesJob,
          args: [{ sponsorable_id: @member_two.id }],
        ) do
          RepositoryOrchestration.transfer(@repo, actor_id: @owner.id, new_owner_id: @member_two.id).execute(synchronous: true)
        end
      end
    end

    test ".transfer_step does not send stratocaster events" do
      assert_equal @repo.owner, @org_one
      T.unsafe(GitHub).reset_stratocaster

      # add a fake step to the orchestration thats guaranteed to write a stratocaster event
      unless TransferRepositoryOrchestration.instance_methods.include?(:emit_event_for_test)
        TransferRepositoryOrchestration.transfer_step :emit_event_for_test do
          GitHub.stratocaster.trigger("CreateEvent", 123)
        end
      end

      perform_enqueued_jobs(only: [ProcessEventJob, UpdateEventFeedsJob]) do
        RepositoryOrchestration.transfer(@repo, actor_id: @owner.id, new_owner_id: @org_two.id, notify_target: true).execute(synchronous: true)
      end

      assert_empty GitHub.stratocaster_store.all
    end

    test "publishes hydro event with expected payload" do
      old_owner = @repo.owner

      RepositoryOrchestration.transfer(@repo, actor_id: @owner.id, new_owner_id: @member_two.id).execute(synchronous: true)

      with_hydro_publisher(GitHub.sync_hydro_publisher) do
        message = {
          repository_id: @repo.id,
          previous_owner: Hydro::EntitySerializer.user(old_owner),
          new_owner: Hydro::EntitySerializer.user(@member_two),
          previous_name: @repo.name,
          new_name: @repo.name,
          new_visibility: @repo.visibility,
          actor_id: @owner.id,
        }
        assert_hydro_published(message, schema: "github.repositories.v1.Transferred", partition_key: @repo.id, ignore_extra_keys: true)
      end
    end

    test "updates license for businesses" do
      old_business = create :business, organizations: [@org_one], owners: [@owner]
      new_business = create :business, organizations: [@org_two], owners: [@owner]
      assert_enqueued_jobs(2, only: BusinessUpdateLicenseUsageJob) do
        RepositoryOrchestration.transfer(@repo, actor_id: @owner.id, new_owner_id: @org_two.id).execute!(synchronous: true)
      end
    end

    test "updates license for business when both orgs are members" do
      org_one_two = create(:organization, admin: @owner)
      old_business = create :business, organizations: [@org_one, org_one_two], owners: [@owner]
      assert_enqueued_jobs(1, only: BusinessUpdateLicenseUsageJob) do
        RepositoryOrchestration.transfer(@repo, actor_id: @owner.id, new_owner_id: org_one_two.id).execute!(synchronous: true)
      end
    end

    test "it locks the repo and descedants during transfer" do
      refute @repo.locked?

      @repo.set_visibility(actor: @orgs_admin, visibility: Repository::PUBLIC_VISIBILITY)

      fork_repo = create(:fork_repository, forker: @orgs_admin, fork_repo: @repo)

      #adding member_two to prevent forked_repo to be inaccessible
      fork_repo.add_member_without_validation_or_notifications(@member_two, action: :admin)

      orchestration = RepositoryOrchestration.transfer(@repo, actor_id: @owner.id, new_owner_id: @member_two.id)
      # Simulating sync phase
      orchestration.execute

      @repo.reload

      # is repository locked?
      assert @repo.locked?
      assert @repo.repository.lock_on_transferring_ownership?

      # Simulate failure during async phase before unlock
      orchestration.repository.stubs(:instrument_search_transfer_ownership_to).raises("boom")
      assert_raises RuntimeError, "boom" do
        orchestration.execute
      end

      @repo.reload
      fork_repo.reload

      # are repository and descedants still locked?
      assert @repo.locked?
      assert @repo.lock_on_transferring_ownership?
      assert fork_repo.locked?
      assert fork_repo.lock_on_transferring_ownership?

      # Simulating successful async retry
      orchestration.repository.unstub(:instrument_search_transfer_ownership_to)
      orchestration.execute

      @repo.reload
      fork_repo.reload

      # repository and descedants are now unlocked
      refute @repo.locked?
      refute fork_repo.locked?

      assert orchestration.succeeded?
    end

    test "it locks the repo owner during transfer" do
      enable_feature_flag(:repo_transfer_owner_lock)

      refute Repositories::RepositoryOwnerLock.locked_for_rename?(owner_id: @repo.owner.id)

      Repositories::RepositoryOwnerLock.expects(:acquire_rename_lock).with(owner_id: @repo.owner.id).once.returns(true)
      # Expected twice, once for :unlock_owner_namespace and once for on_end_orchestration
      Repositories::RepositoryOwnerLock.expects(:release_rename_lock).with(owner_id: @repo.owner.id).twice

      orchestration = RepositoryOrchestration.transfer(@repo, actor_id: @owner.id, new_owner_id: @member_two.id)
      orchestration.execute(synchronous: true)

      refute Repositories::RepositoryOwnerLock.locked_for_rename?(owner_id: @repo.owner.id)
    end

    test "it does not lock the repo owner during transfer" do
      refute Repositories::RepositoryOwnerLock.locked_for_rename?(owner_id: @repo.owner.id)

      Repositories::RepositoryOwnerLock.expects(:acquire_rename_lock).with(owner_id: @repo.owner.id).never
      Repositories::RepositoryOwnerLock.expects(:release_rename_lock).with(owner_id: @repo.owner.id).never

      orchestration = RepositoryOrchestration.transfer(@repo, actor_id: @owner.id, new_owner_id: @member_two.id)
      orchestration.execute(synchronous: true)

      refute Repositories::RepositoryOwnerLock.locked_for_rename?(owner_id: @repo.owner.id)
    end
  end

  context "unpublish_pages", skip_enterprise: true, skip_with_all_emus: true do
    test "should soft delete page when new owner does not support private page" do
      enable_feature_flag(:pages_soft_deletion)

      @owner.update!(plan: "business_plus")
      page = create(:private_page, repository: @repo)
      assert page.private?

      RepositoryOrchestration.transfer(@repo, actor_id: @owner.id, new_owner_id: @org_two.id).execute(synchronous: true)

      assert page.reload.soft_deleted?
    end

    test "should unpublish page when owner does not support private page when soft delete is not enabled" do
      disable_feature_flag(:pages_soft_deletion)

      @org_one.update!(plan: "business_plus")
      page = create(:private_page, repository: @repo)
      assert page.private?

      RepositoryOrchestration.transfer(@repo, actor_id: @owner.id, new_owner_id: @org_two.id).execute(synchronous: true)

      assert_raises(ActiveRecord::RecordNotFound) do
        assert page.reload
      end
    end

    test "should restore page when new owner supports private page" do
      enable_feature_flag(:pages_soft_deletion)

      @org_one.update!(plan: "free")
      page = create(:private_page, repository: @repo)
      page.soft_delete!

      @org_two.update!(plan: "business_plus")

      RepositoryOrchestration.transfer(@repo, actor_id: @owner.id, new_owner_id: @org_two.id).execute(synchronous: true)

      refute page.reload.soft_deleted?
    end

    test "should soft delete page when new owner does not support page on private repos" do
      enable_feature_flag(:pages_soft_deletion)

      @org_one.update!(plan: "business")
      @repo.update!(public: false)
      page = create(:page, repository: @repo)
      page.update!(public: true)

      @org_two.update!(plan: "free")

      RepositoryOrchestration.transfer(@repo, actor_id: @owner.id, new_owner_id: @org_two.id).execute(synchronous: true)

      assert page.reload.soft_deleted?
    end

    test "should restore page when new owner supports page on private repo" do
      enable_feature_flag(:pages_soft_deletion)

      @org_one.update!(plan: "free")
      page = create(:page, repository: @repo)
      @repo.update!(public: false)
      page.soft_delete!

      @org_two.update!(plan: "business_plus")

      RepositoryOrchestration.transfer(@repo, actor_id: @owner.id, new_owner_id: @org_two.id).execute(synchronous: true)

      refute page.reload.soft_deleted?
    end
  end

  context "rulesets" do
    test "should move associated rulesets without bypass actors" do
      create :repository_ruleset, :repo_admin_bypass, :org_admin_bypass_any, :deploy_key_bypass, source: @repo

      RepositoryOrchestration.transfer(@repo, actor_id: @owner.id, new_owner_id: @org_two.id).execute(synchronous: true)

      assert_equal 1, @repo.rulesets.count

      ruleset = @repo.rulesets.first
      assert_equal 0, ruleset.bypass_actors.count
    end
  end
end
