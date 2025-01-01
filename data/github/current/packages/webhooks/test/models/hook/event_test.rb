# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

class Hook
  class Event
    extend T::Helpers

    class EventTestEvent < Hook::Event
      supports_targets Business, Repository, Organization, Integration, Marketplace::Listing
      event_attr :foo, :target_repository

      def deliverable?
        target_repository.present?
      end
    end

    class EventTestImportingEvent < Hook::Event
      supports_targets Business, Repository, Organization, Integration, Marketplace::Listing
      event_attr :foo, :target_repository

      def model_importing?
        target_repository.locked_on_migration?
      end
    end

    class EventTestWithOveridesEvent < Hook::Event
      supports_targets Business, Repository, Organization, Integration, Marketplace::Listing

      event_attr :target_repository, :target_organization,
        :target_marketplace_listing, :target_sponsors_listing, :actor
    end

    class EventWithRequiredAttr < Hook::Event
      supports_targets Business, Repository, Organization, Integration, Marketplace::Listing
      event_attr :actor_id, required: true
    end

    class EventWithToBeRequiredAttr < Hook::Event
      supports_targets Business, Repository, Organization, Integration, Marketplace::Listing
      event_attr :actor_id, to_be_required: true
    end

    class EventWithFeatureFlagAndNoActions < Hook::Event
      supports_targets Business, Repository, Organization, Integration, Marketplace::Listing
      event_attr :target_repository, :target_organization, required: true

      feature_flag :preview_hook_events
    end

    class EventWithFeatureFlagAndAnAction < Hook::Event
      supports_targets Business, Repository, Organization, Integration, Marketplace::Listing
      event_attr :target_repository, :target_organization, required: true
      event_attr :action

      feature_flag :preview_hook_events, actions: ["some-action"]
    end

    class EventWithCustomVisibility < Hook::Event
      supports_targets Business, Repository, Organization, Integration, Marketplace::Listing
      event_attr :target_repository, :target_organization, required: true
      event_attr :action

      feature_flag :preview_hook_events

      def self.visible_for?(user, target)
        target.feature_enabled?(:preview_hook_events)
      end
    end

    class TestRepositoryEvent < EventTestWithOveridesEvent
      supports_targets Repository
    end

    class EventTestWithTypeEvent < Hook::Event
      event_attr :target_repository, :event_type
    end

    class EventTestImportingOldRepositoryEvent < Hook::Event
      supports_targets Repository
      event_attr :foo, :target_repository
    end
  end

  class Payload
    class EventTestPayload < ::Hook::Payload
    end
  end
end

class HookEventTest < GitHub::TestCase
  include PermissionsHelper
  include GitHub::LoggerHelper
  include HydroTestHelpers
  include DogstatsTestHelpers

  EventTestEvent = Hook::Event::EventTestEvent
  EventTestImportingEvent = Hook::Event::EventTestImportingEvent
  WithOverridesEvent = Hook::Event::EventTestWithOveridesEvent
  EventWithRequiredAttr = Hook::Event::EventWithRequiredAttr
  EventWithToBeRequiredAttr = Hook::Event::EventWithToBeRequiredAttr
  EventWithFeatureFlagAndNoActions = Hook::Event::EventWithFeatureFlagAndNoActions
  EventWithFeatureFlagAndAnAction = Hook::Event::EventWithFeatureFlagAndAnAction
  TestRepositoryEvent = Hook::Event::TestRepositoryEvent
  EventTestWithTypeEvent = Hook::Event::EventTestWithTypeEvent
  EventTestImportingOldRepositoryEvent = Hook::Event::EventTestImportingOldRepositoryEvent

  fixtures do
    @org = create(:organization)
    @user_repo = create(:repository)
    @repo = create(:repository)
    @user = create(:user)
    @org_repo = create :repository, owner: @org

    @business_org = create(:organization)
    @business = create(:business, organizations: [@business_org])

    @org_hook = create :hook, :org, events: %w(*), installation_target: @org
    @org_repo_hook = create :hook, :web, events: %w(*), installation_target: @org_repo
    @user_repo_hook = create :hook, :web, events: %w(*), installation_target: @user_repo
    @business_org_hook = create :hook, :org, events: %w(*), installation_target: @business_org
    @business_hook = create :hook, :org, events: %w(*), installation_target: @business

    @integration = Integration::Events.stub_const(:SUPPORTED_EVENTS, %w(event_test_with_overides)) do
      Integration::Events.stub_const(:RESOURCE_TO_EVENTS, { "metadata" => %w(event_test_with_overides) }) do
        create(:integration, :with_active_hook, default_permissions: { "metadata" => :read }, default_events: %w(event_test_with_overides))
      end
    end

    make_trusted_oauth_apps_owner

    @integration_hook = @integration.hook
  end

  setup do
    Hook.stubs(:delivers_in_test?).returns(true)
    @time = Time.parse("2014-04-07 12:00:00 -0700")
  end

  context ".guid" do
    test "uses provided guid" do
      mock_guid = "b0ea3916-558d-11ef-9c78-195fd6da0d56"
      event = EventTestEvent.new(action: "tested", triggered_at: Time.now, event_guid: mock_guid)
      assert_equal(mock_guid, event.guid)
    end

    test "uses generated guid" do
      generated_guid = "9e83ccb0-54bb-11ef-8355-d2519c14d59c"
      SimpleUUID::UUID.any_instance.expects(:to_guid).once.returns(generated_guid)
      event = EventTestEvent.new foo: "bar", triggered_at: Time.now
      assert_equal(generated_guid, event.guid)
    end
  end

  context ".queue" do
    test "queues a job for DeliverHookEvent" do
      Timecop.freeze(Time.now) do
        time = Time.parse("2014-04-07 12:00:00 -0700")

        EventTestEvent.queue foo: "bar", triggered_at: @time

        assert_enqueued_with job: DeliverHookEventJob, args: ->(args) {
          args[0] == "event_test" &&
            args[1][:foo] == "bar" &&
            args[1][:triggered_at] == time &&
            args[1][:queued_at].to_i == Time.now.to_i
        }
      end
    end

    test "instruments and skips events with missing required attributes" do
      error = assert_raises Hook::Event::MissingRequiredAttribute do
        EventWithRequiredAttr.queue actor_id: nil, triggered_at: @time
      end

      assert_equal "github-event-dispatch", error.failbot_context["app"]
    end

    test "asserts that nothing fires when asked to skip" do
      Hook.stubs(:delivers_in_test?).returns(nil)
      Hook::DeliverySystem.expects(:deliver).never

      EventWithRequiredAttr.queue actor_id: nil, triggered_at: @time
    end
  end

  context ".for_event_type" do
    test "initializes the correct Hook::Event model for the passed event type" do
      event = Hook::Event.for_event_type("event_test")

      assert event.instance_of?(Hook::Event::EventTestEvent)
    end

    test "initializes the model with the passed attributes" do
      event = Hook::Event.for_event_type("event_test", foo: "bar")

      assert_equal "bar", T.unsafe(event).foo
    end
  end

  context ".visible_for?" do
    test "returns false when the user is not feature flagged on" do
      # test that we ignore the feature flag status of the installation target.
      # only events that override .visible_for? should make use of it.
      enable_feature_flag(:preview_hook_events, @user_repo)
      disable_feature_flag(:preview_hook_events, @user)
      refute Hook::Event::EventWithFeatureFlagAndNoActions.visible_for?(@user, @user_repo)
    end

    test "returns true when the user is feature flagged on" do
      enable_feature_flag(:preview_hook_events, @user)
      assert Hook::Event::EventWithFeatureFlagAndNoActions.visible_for?(@user, nil)
    end

    test "returns true when the event has feature flagged actions" do
      disable_feature_flag(:preview_hook_events, @user)
      assert Hook::Event::EventWithFeatureFlagAndAnAction.visible_for?(@user, nil)
    end

    test "can be overridden by individual events to base visibility on an installation target" do
      enable_feature_flag(:preview_hook_events, @user_repo)
      assert Hook::Event::EventWithCustomVisibility.visible_for?(nil, @user_repo)
    end
  end

  context "multi-tenant enterprise" do
    test "sets the tenant on the event when present in multi-tenant mode", skip_enterprise: true do
      business = create(:business)
      on_multi_tenant_enterprise(tenant: business) do
        event = EventTestEvent.new
        assert_equal business, event.tenant
      end
    end

    test "tenant not set when not in multi-tenant mode" do
      event = EventTestEvent.new
      refute event.tenant
    end

    test "#headers_for returns tenant header when present in multi-tenant mode", skip_enterprise: true do
      business = create(:business)
      on_multi_tenant_enterprise(tenant: business) do
        event = EventTestEvent.new
        assert_equal business, event.tenant
        headers = event.headers_for(:hook)
        assert_equal 2, headers.count
        assert_includes headers, { "X-GitHub-Tenant" => "#{business.slug}" }
        assert_includes headers, { "X-GitHub-Tenant-ID" => "#{business.id}" }
      end
    end

    test "#headers_for returns no tenant headers when no tenant", skip_enterprise: true do
      business = create(:business)
      on_multi_tenant_enterprise do
        event = EventTestEvent.new
        refute event.tenant
        headers = event.headers_for(:hook)
        assert_equal 0, headers.count
        assert_empty headers
      end
    end
  end

  context "#triggered_at" do
    test "returns the passed time" do
      time = Time.utc(2014, 7, 4, 19)
      event = EventTestEvent.new(triggered_at: time)

      assert_equal time, T.unsafe(event).triggered_at
    end

    test "returns the correct time if given an int" do
      event = EventTestEvent.new(triggered_at: 1396897200)

      assert_equal Time.parse("2014-04-07 12:00:00 -0700"), T.unsafe(event).triggered_at
    end

    test "returns the parsed time if given a string" do
      event = EventTestEvent.new(triggered_at: "2014-04-07T12:00:00-07:00")

      assert_equal Time.parse("2014-04-07 12:00:00 -0700"), T.unsafe(event).triggered_at
    end

    test "is set to current time if not given" do
      Timecop.freeze(expected_time = @time) do
        event = EventTestEvent.new
        assert_equal expected_time, T.unsafe(event).triggered_at
      end
    end
  end

  context "#event_type" do
    test "parses the event type from the class name" do
      event = EventTestEvent.new
      assert_equal "event_test", event.event_type
    end
  end

  context "#deliver" do
    test "delegates the delivery to Hook::DeliverySystem the event is deliverable" do
      event = EventTestEvent.new target_repository: @user_repo
      Hook::DeliverySystem.expects(:deliver).with(event)

      assert event.deliverable?
      event.deliver
    end

    test "does NOT attempt delivery if the event is not deliverable" do
      event = EventTestEvent.new target_repository: nil
      Hook::DeliverySystem.expects(:deliver).never

      refute event.deliverable?
      event.deliver
    end

    context "model_importing?" do
      context "when repository is young" do
        test "does NOT attempt delivery if the repository is importing" do
          GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

          @user_repo.lock_for_migration
          @user_repo.update!(created_at: 1.week.ago)
          event = EventTestImportingOldRepositoryEvent.new(target_repository: @user_repo)

          Hook::DeliverySystem.expects(:deliver).never

          assert event.model_importing?
          event.deliver

          tags = ["event:hook/event_test_importing_old_repository", "event_type:hook/event_test_importing_old_repository", "fn:deliver"]
          stats = GitHub.dogstats.increments("hooks.disabled_for_import", tags: tags)
          assert_equal 1, stats.count

          assert_hydro_published(
            {
              event_type: event.event_type,
              event_action: event.attributes[:action],
              filtered_reason: "disabled_for_import",
              guid: event.guid,
              target_repository_id: @user_repo.id,
              target_organization_id: nil,
              triggered_at:  event.attributes[:triggered_at],
              request_id: GitHub.context[:request_id]
            }, schema: "github.webhooks.v0.DroppedEventMetadata"
          )
        end

        test "attempts delivery if the repository is not importing" do
          GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

          @user_repo.update!(created_at: 1.week.ago)
          event = EventTestImportingOldRepositoryEvent.new(target_repository: @user_repo)

          Hook::DeliverySystem.expects(:deliver).with(event)

          assert !event.model_importing?
          event.deliver
        end
      end

      context "when repository is old" do
        test "does NOT attempt delivery if the repository is importing" do
          GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

          @user_repo.lock_for_migration
          @user_repo.update!(created_at: 1.year.ago)
          disable_feature_flag(:skip_model_importing_check_on_old_repositories, @user_repo)
          event = EventTestImportingOldRepositoryEvent.new(target_repository: @user_repo)


          Hook::DeliverySystem.expects(:deliver).never

          assert event.model_importing?
          event.deliver

          tags = ["event:hook/event_test_importing_old_repository", "event_type:hook/event_test_importing_old_repository", "fn:deliver"]
          stats = GitHub.dogstats.increments("hooks.disabled_for_import", tags: tags)
          assert_equal 1, stats.count

          assert_hydro_published(
            {
              event_type: event.event_type,
              event_action: event.attributes[:action],
              filtered_reason: "disabled_for_import",
              guid: event.guid,
              target_repository_id: @user_repo.id,
              target_organization_id: nil,
              triggered_at:  event.attributes[:triggered_at],
              request_id: GitHub.context[:request_id]
            }, schema: "github.webhooks.v0.DroppedEventMetadata"
          )
        end

        test "does not attempt delivery if the repository is locked for migration" do
          GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

          @user_repo.lock_for_migration
          @user_repo.update!(created_at: 1.year.ago)

          enable_feature_flag(:skip_model_importing_check_on_old_repositories, @user_repo)
          event = EventTestImportingOldRepositoryEvent.new(target_repository: @user_repo)


          Hook::DeliverySystem.expects(:deliver).with(event).never

          assert event.model_importing?
          event.deliver
        end

        test "attempts delivery if an old repository is importing with feature flag" do
          GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

          @user_repo.update!(created_at: 1.year.ago)

          enable_feature_flag(:skip_model_importing_check_on_old_repositories, @user_repo)
          event = EventTestImportingOldRepositoryEvent.new(target_repository: @user_repo)


          Hook::DeliverySystem.expects(:deliver).with(event)

          refute event.model_importing?
          event.deliver
        end

        test "attempts delivery if the repository is not importing" do
          GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

          @user_repo.update!(created_at: 1.year.ago)
          event = EventTestImportingOldRepositoryEvent.new(target_repository: @user_repo)

          Hook::DeliverySystem.expects(:deliver).with(event)

          assert !event.model_importing?
          event.deliver
        end
      end
    end

    test "does deliver if event meets feature_flag_enabled? requirements" do
      enable_feature_flag(:preview_hook_events, @org)
      event = EventWithFeatureFlagAndNoActions.new target_repository: @org_repo, target_organization: @org
      Hook::DeliverySystem.expects(:deliver).with(event)

      event.deliver
    end

    test "does deliver if event meets feature_flag_enabled? with irrelevant action requirements" do
      enable_feature_flag(:preview_hook_events, @org)
      event = EventWithFeatureFlagAndNoActions.new target_repository: @org_repo, target_organization: @org, action: "irrelevant"
      Hook::DeliverySystem.expects(:deliver).with(event)

      event.deliver
    end

    test "does not deliver if event meets feature_flag_enabled? requirement is not met" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      disable_feature_flag(:preview_hook_events, @org)
      event = EventWithFeatureFlagAndNoActions.new target_repository: @org_repo, target_organization: @org
      request_id = SecureRandom.uuid
      GitHub.context.push(request_id: request_id)

      Hook::DeliverySystem.expects(:deliver).with(event).never

      event.deliver
      tags = ["event:hook/event_with_feature_flag_and_no_actions", "event_type:hook/event_with_feature_flag_and_no_actions"]
      stats = GitHub.dogstats.increments("hooks.disabled_by_feature_flag", tags: tags)
      assert_equal 1, stats.count

      assert_hydro_published(
        {
          event_type: event.event_type,
          event_action: event.attributes[:action],
          filtered_reason: "disabled_by_feature_flag",
          guid: event.guid,
          target_repository_id: @org_repo.id,
          target_organization_id: event.target_organization&.id,
          triggered_at:  event.attributes[:triggered_at],
          request_id: request_id
        }, schema: "github.webhooks.v0.DroppedEventMetadata"
      )
    end

    test "does deliver if event meets feature_flag_enabled? and action requirements" do
      enable_feature_flag(:preview_hook_events, @org)
      event = EventWithFeatureFlagAndAnAction.new target_repository: @org_repo, target_organization: @org, action: "some-action"
      Hook::DeliverySystem.expects(:deliver).with(event)

      event.deliver
    end

    test "does deliver if event does not meet feature_flag_enabled? requirement but has an irrelevant action" do
      disable_feature_flag(:preview_hook_events, @org)
      event = EventWithFeatureFlagAndAnAction.new target_repository: @org_repo, target_organization: @org, action: "irrelevant"
      Hook::DeliverySystem.expects(:deliver).with(event)

      event.deliver
    end

    test "does not deliver if event does not meet feature_flag_enabled? requirement but has a relevant action" do
      disable_feature_flag(:preview_hook_events, @org)
      event = EventWithFeatureFlagAndAnAction.new target_repository: @org_repo, target_organization: @org, action: "some-action"
      request_id = SecureRandom.uuid
      GitHub.context.push(request_id: request_id)

      Hook::DeliverySystem.expects(:deliver).with(event).never
      event.deliver

      assert_hydro_published(
        {
          event_type: event.event_type,
          event_action: event.attributes[:action],
          filtered_reason: "disabled_by_feature_flag",
          guid: event.guid,
          target_repository_id: @org_repo.id,
          target_organization_id: @org.id,
          triggered_at:  event.attributes[:triggered_at],
          request_id: request_id
        }, schema: "github.webhooks.v0.DroppedEventMetadata"
      )
    end

    test "still delivers if target_repository is disabled via org repo owner" do
      org = create(:organization, plan: "silver")
      repo = create :private_repository, owner: org, created_by_user_id: @user.id
      hook = create(:hook, :web, installation_target: repo)
      org.disable!
      org.reload

      event = EventTestEvent.new target_repository: repo
      Hook::DeliverySystem.expects(:deliver).with(event)
      event.deliver
    end

    test "does NOT deliver if target_repository is an advisory workspace" do
      disable_feature_flag(:maintainer_love_advisory_workspaces_can_use_actions)
      advisory = create(:repository_advisory, repository: @org_repo, author: @org.admins.first)
      request_id = SecureRandom.uuid
      GitHub.context.push(actor_id: @org.admins.first.id, request_id: request_id)
      workspace = RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(advisory, @org.admins.first)
      hook = create(:hook, :web, installation_target: workspace)

      event = EventTestEvent.new target_repository: workspace
      Hook::DeliverySystem.expects(:deliver).never
      event.deliver

      assert_hydro_published(
        {
          event_type: event.event_type,
          event_action: event.attributes[:action],
          filtered_reason: "target_repository_disallows_hooks",
          guid: event.guid,
          target_repository_id: workspace.id,
          target_organization_id: @org.id,
          triggered_at:  event.attributes[:triggered_at],
          request_id: request_id
        }, schema: "github.webhooks.v0.DroppedEventMetadata"
      )
    end

    test "records timing for deliverability checks in DataDog" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      event = EventWithFeatureFlagAndAnAction.new target_repository: @org_repo, target_organization: @org, action: "some-action"
      event.deliver

      expected_tags = [
        "event:hook/event_with_feature_flag_and_an_action_some-action",
        "event_type:hook/event_with_feature_flag_and_an_action",
      ]

      assert_equal 1, GitHub.dogstats.distributions("hooks.jit_deliverability", tags: expected_tags).count
    end
  end

  context "#deliver_later" do
    test "queues a job for DeliverHookEvent" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      time = Time.parse("2014-04-07 12:00:00 -0700")
      attrs = { foo: "bar", target_repository: @user_repo, triggered_at: time, delivered_hook_ids: [] }

      EventTestEvent.new(attrs).deliver_later

      assert_enqueued_with job: DeliverHookEventJob, queue: "deliver_hook_event", args: ["event_test", attrs]
      assert_equal 1, GitHub.dogstats.increments("hooks.job_enqueued.count").count
    end

    test "includes cluster information in metrics" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      DatabaseSelector::ReplicationState.stubs(:current).returns(DatabaseSelector::ReplicationState.new)
      DatabaseSelector::ReplicationState.any_instance.stubs(:to_hash).returns({
        mysql1: { gtid: "000-000", time: Time.now.to_i }
      })

      attrs = { foo: "bar", target_repository: @user_repo, triggered_at: Time.now, delivered_hook_ids: [] }
      EventTestEvent.new(attrs).deliver_later
      assert_enqueued_with job: DeliverHookEventJob, queue: "deliver_hook_event", args: ["event_test", attrs]

      stats = GitHub.dogstats.increments("hooks.job_enqueued.count")
      assert_equal 1, stats.count
      stats = GitHub.dogstats.increments("hooks.mysql.cluster.touched")
      assert_equal 1, stats.count
      assert stats[0].tags.any? { |t| t.starts_with?("cluster:mysql1") }
    end

    test "emits tier1 event size metric" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      attrs = { foo: "bar", target_repository: @user_repo, triggered_at: Time.now, delivered_hook_ids: [] }
      EventTestEvent.new(attrs).deliver_later
      assert_enqueued_with job: DeliverHookEventJob, queue: "deliver_hook_event", args: ["event_test", attrs]

      expected_tags = [
        "event:hook/event_test",
        "event_type:hook/event_test",
        "fn:deliver_later",
        "prehydrated:false"
      ]
      assert_equal 1, GitHub.dogstats.distributions("hooks.tier1_event_size", tags: expected_tags).count
    end

    test "does deliver if event meets feature_flag_enabled? requirements" do
      enable_feature_flag(:preview_hook_events, @org)
      event = EventWithFeatureFlagAndNoActions.new target_repository: @org_repo, target_organization: @org
      event.deliver_later

      assert_enqueued_with job: DeliverHookEventJob, queue: "deliver_hook_event", args: [event.event_type, event.attributes]
    end

    test "does deliver if event meets feature_flag_enabled? with irrelevant action requirements" do
      enable_feature_flag(:preview_hook_events, @org)
      event = EventWithFeatureFlagAndNoActions.new target_repository: @org_repo, target_organization: @org, action: "irrelevant"
      event.deliver_later

      assert_enqueued_with job: DeliverHookEventJob, queue: "deliver_hook_event", args: [event.event_type, event.attributes]
    end

    test "does not deliver if event feature_flag_enabled? requirement is not met" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      disable_feature_flag(:preview_hook_events, @org)
      event = EventWithFeatureFlagAndNoActions.new target_repository: @org_repo, target_organization: @org

      event.deliver_later
      assert_enqueued_jobs 0, only: DeliverHookEventJob

      assert_hydro_published(
        {
          event_type: event.event_type,
          event_action: event.attributes[:action],
          filtered_reason: "disabled_by_feature_flag",
          guid: event.guid,
          target_repository_id: @org_repo.id,
          target_organization_id: @org.id,
          triggered_at:  event.attributes[:triggered_at],
          request_id: GitHub.context[:request_id]
        }, schema: "github.webhooks.v0.DroppedEventMetadata"
      )

      expected_tags = [
        "event:hook/event_with_feature_flag_and_no_actions",
        "fn:deliver_later",
      ]
      assert_equal 1, GitHub.dogstats.increments("hooks.disabled_by_feature_flag", tags: expected_tags).count
    end

    test "does deliver if event meets feature_flag_enabled? and action requirements" do
      enable_feature_flag(:preview_hook_events, @org)
      event = EventWithFeatureFlagAndAnAction.new target_repository: @org_repo, target_organization: @org, action: "some-action"
      event.deliver_later

      assert_enqueued_with job: DeliverHookEventJob, queue: "deliver_hook_event", args: [event.event_type, event.attributes]
    end

    test "does deliver if event does not meet feature_flag_enabled? requirement but has an irrelevant action" do
      disable_feature_flag(:preview_hook_events, @org)
      event = EventWithFeatureFlagAndAnAction.new target_repository: @org_repo, target_organization: @org, action: "irrelevant"
      event.deliver_later

      assert_enqueued_with job: DeliverHookEventJob, queue: "deliver_hook_event", args: [event.event_type, event.attributes]
    end

    test "does not deliver if event does not meet feature_flag_enabled? requirement but has a relevant action" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      disable_feature_flag(:preview_hook_events, @org)
      event = EventWithFeatureFlagAndAnAction.new target_repository: @org_repo, target_organization: @org, action: "some-action"
      event.deliver_later

      assert_no_enqueued_jobs only: DeliverHookEventJob

      expected_tags = [
        "event:hook/event_with_feature_flag_and_an_action_some-action",
        "fn:deliver_later",
      ]
      assert_equal 1, GitHub.dogstats.increments("hooks.disabled_by_feature_flag", tags: expected_tags).count
    end
  end

  context "#target_repository" do
    test "is nil by default and should be overridden by the event subclass" do
      event = EventTestEvent.new
      assert_nil event.target_repository
    end
  end

  context "#target_organization" do
    test "by default is nil if the target repo is nil" do
      event = EventTestEvent.new target_repository: nil

      assert_nil event.target_organization
    end

    test "returns nil if the target repo has a nil owner" do
      nil_owner_repo = create(:repository, created_by_user_id: @user.id)
      nil_owner_repo.owner = nil

      event = EventTestEvent.new target_repository: nil_owner_repo

      assert_nil event.target_organization
    end

    test "returns nil if the target repo is owned by a user" do
      event = EventTestEvent.new target_repository: @user_repo

      assert_nil event.target_organization
    end

    test "returns target repo's owner if the target repo is owned by an org" do
      event = EventTestEvent.new target_repository: @org_repo

      assert_equal @org, event.target_organization
    end
  end

  context "#target_business" do
    if GitHub.single_business_environment?
      test "returns the global business" do
        event = WithOverridesEvent.new target_organization: nil

        assert_equal GitHub.global_business, event.target_business
      end
    else
      test "by default is nil if the target organization is nil" do
        event = WithOverridesEvent.new target_organization: nil

        assert_nil event.target_business
      end

      test "returns nil if the target organization is not in a business" do
        event = WithOverridesEvent.new target_organization: @org

        assert_nil event.target_business
      end

      test "returns target org's business if the target org is in a business" do
        event = WithOverridesEvent.new target_organization: @business_org

        assert_equal @business, event.target_business
      end
    end
  end

  context "#actor" do
    test "raises a NotImplementedError if not overridden" do
      event = EventTestEvent.new

      assert_raises NotImplementedError do
        event.actor
      end
    end
  end

  context "#subscribed_hooks" do
    if GitHub.single_business_environment?
      test "always includes a global business hook" do
        event = WithOverridesEvent.new target_repository: nil, target_organization: nil

        assert_includes event.subscribed_hooks, @business_hook
      end
    else
      test "returns an empty array if there is no target repo or org" do
        event = WithOverridesEvent.new target_repository: nil, target_organization: nil

        assert_equal [], event.subscribed_hooks
      end
    end

    test "includes repo hooks from the target repo" do
      event = WithOverridesEvent.new target_repository: @user_repo, target_organization: nil

      assert_includes event.subscribed_hooks, @user_repo_hook
    end

    test "includes org hooks from the target org" do
      event = WithOverridesEvent.new target_repository: nil, target_organization: @org

      assert_includes event.subscribed_hooks, @org_hook
    end

    test "includes integration hooks for integrations installed on the target repo" do
      events_to_permissions = {
        "metadata" => %w(event_test_with_overides),
      }

      Integration::Events.stub_const(:RESOURCE_TO_EVENTS, events_to_permissions) do
        @integration.install_on(
          @org,
          repositories: [@org_repo],
          installer: @org.admins.first,
          entry_point: :test_case
        )
      end

      Integration::Events.stub_const(:RESOURCE_TO_EVENTS, events_to_permissions) do
        event = WithOverridesEvent.new target_repository: @org_repo, target_organization: @org
        assert_includes event.subscribed_hooks, @integration_hook
      end
    end

    test "does not include integration hooks for suspended integrations" do
      events_to_permissions = {
        "metadata" => %w(event_test_with_overides),
      }

      Integration::Events.stub_const(:RESOURCE_TO_EVENTS, events_to_permissions) do
        @integration.install_on(
          @org,
          repositories: [@org_repo],
          installer: @org.admins.first,
          entry_point: :test_case
        )
      end

      @integration.suspend(actor: create(:staff_admin_user), reason: "test")

      Integration::Events.stub_const(:RESOURCE_TO_EVENTS, events_to_permissions) do
        event = WithOverridesEvent.new target_repository: @org_repo, target_organization: @org
        refute_includes event.subscribed_hooks, @integration_hook
      end
    end

    test "does not include integration hooks for suspended installations on the target repo" do
      events_to_permissions = {
        "metadata" => %w(event_test_with_overides),
      }

      Integration::Events.stub_const(:RESOURCE_TO_EVENTS, events_to_permissions) do
        result = @integration.install_on(@org, repositories: [@org_repo], installer: @org.admins.first, entry_point: :test_case)
        result.installation.suspend!
      end

      Integration::Events.stub_const(:RESOURCE_TO_EVENTS, events_to_permissions) do
        event = WithOverridesEvent.new target_repository: @org_repo, target_organization: @org
        refute_includes event.subscribed_hooks, @integration_hook
      end
    end

    test "includes integration hooks for an integration installed on the target repo and a different integration installed on the target org" do
      events_to_permissions = {
        "metadata" => %w(event_test_with_overides), # Repo event
        "members" => %w(event_test_with_overides),  # Org event
      }

      repo_based_integration = T.let(nil, T.untyped)
      org_based_integration = T.let(nil, T.untyped)

      Integration::Events.stub_const(:SUPPORTED_EVENTS, %w(event_test_with_overides)) do
        Integration::Events.stub_const(:RESOURCE_TO_EVENTS, events_to_permissions) do
          repo_based_integration = T.unsafe(self).create(:integration, :with_active_hook, default_events: %w(event_test_with_overides), default_permissions: { "metadata" => :read })
          org_based_integration = T.unsafe(self).create(:integration, :with_active_hook, default_events: %w(event_test_with_overides), default_permissions: { "members" => :read })
        end
      end

      Integration::Events.stub_const(:RESOURCE_TO_EVENTS, events_to_permissions) do
        T.unsafe(repo_based_integration).install_on(
          @org,
          repositories: [@org_repo],
          installer: @org.admins.first,
          entry_point: :test_case
        )

        T.unsafe(org_based_integration).install_on(
          @org,
          repositories: [@org_repo],
          installer: @org.admins.first,
          entry_point: :test_case
        )

      end

      Integration::Events.stub_const(:RESOURCE_TO_EVENTS, events_to_permissions) do
        event = WithOverridesEvent.new target_repository: @org_repo, target_organization: @org
        assert_includes event.subscribed_hooks, T.unsafe(repo_based_integration).hook
        assert_includes event.subscribed_hooks, T.unsafe(org_based_integration).hook
      end
    end

    test "does not include integration hooks for integrations NOT installed on the target repo" do
      repo_a = create(:repository, owner: @org, created_by_user_id: @user.id)
      repo_b = create(:repository, owner: @org, created_by_user_id: @user.id)

      @integration.install_on(
        @org,
        repositories: [repo_a],
        installer: @org.admins.first,
        entry_point: :test_case
      )
      event = WithOverridesEvent.new target_repository: repo_b, target_organization: @org

      refute_includes event.subscribed_hooks, @integration_hook
    end

    test "only returns integration hooks for organization owned repositories on which the integration has permission" do
      repo_a = create(:repository, owner: @org, created_by_user_id: @user.id)
      repo_b = create(:repository, owner: @org, created_by_user_id: @user.id)

      integration = make_integration_installation(
        repository: repo_a,
        permissions: { "repository_projects" => :read },
        events: %w(project_card),
      ).integration

      event = WithOverridesEvent.new target_repository: repo_b, target_organization: @org

      event.stubs(:event_type).returns("project_card")

      refute_includes event.subscribed_hooks, integration.hook
    end

    test "does include integration hooks for integrations installed on the target repo when the event is both an org and repo event" do
      repo_a = create(:repository, owner: @org, created_by_user_id: @user.id)

      integration = create(:integration, :with_active_hook, default_permissions: { "organization_projects" => :read }, default_events: %w(project_card))
      make_integration_installation(integration: integration, repository: repo_a)

      event = WithOverridesEvent.new target_repository: repo_a, target_organization: @org

      event.stubs(:event_type).returns("project_card")

      assert_includes event.subscribed_hooks, integration.hook
    end

    test "includes org and repo hooks if both targets are set" do
      event = WithOverridesEvent.new target_repository: @org_repo, target_organization: @org

      assert_includes event.subscribed_hooks, @org_hook
      assert_includes event.subscribed_hooks, @org_repo_hook
    end

    test "does not include inactive repo hooks" do
      @org_repo_hook.update(active: false)
      event = WithOverridesEvent.new target_repository: @org_repo, target_organization: @org

      refute_includes event.subscribed_hooks, @org_repo_hook
    end

    test "does not include inactive org hooks" do
      @org_hook.update(active: false)
      event = WithOverridesEvent.new target_repository: @org_repo, target_organization: @org

      refute_includes event.subscribed_hooks, @org_hook
    end

    test "does not include inactive integration hooks" do
      @integration.install_on(
        @org,
        repositories: [@org_repo],
        installer: @org.admins.first,
        entry_point: :test_case
      )
      @integration_hook.reload.update(active: false)
      event = WithOverridesEvent.new target_repository: @org_repo

      refute_includes event.subscribed_hooks, @integration_hook
    end

    test "does not include repo hooks which don't listen to the event type" do
      push_only_repo_hook = create :hook, :web, events: %w(push), installation_target: @user_repo
      event = WithOverridesEvent.new target_repository: @user_repo, target_organization: nil

      refute_includes event.subscribed_hooks, push_only_repo_hook
    end

    test "does not include org hooks which don't listen to the event type" do
      push_only_org_hook = create :hook, :org, events: %w(push), installation_target: @org
      event = WithOverridesEvent.new target_repository: @org_repo, target_organization: @org

      refute_includes event.subscribed_hooks, push_only_org_hook
    end

    test "does not include integration hooks which don't have an installation that listens to the event type" do
      installation = @integration.install_on(
        @org,
        repositories: [@org_repo],
        installer: @org.admins.first,
        entry_point: :test_case
      ).installation

      installation.events = %w(push)
      installation.save!

      event = WithOverridesEvent.new target_repository: @org_repo, target_organization: @org

      refute_includes event.subscribed_hooks, @integration_hook
    end

    test "includes integration hooks for integrations installed on the target org for an org-only based event" do
      integration = Integration::Events.stub_const(:SUPPORTED_EVENTS, %w(event_test_with_overides)) do
        Integration::Events.stub_const(:RESOURCE_TO_EVENTS, { "members" => %w(event_test_with_overides) }) do
          create(:integration, :with_active_hook, default_events: %w(event_test_with_overides), default_permissions: { "members" => :read })
        end
      end
      integration_hook = integration.hook

      events_to_permissions = {
        "members" => %w(event_test_with_overides),
      }

      Integration::Events.stub_const(:RESOURCE_TO_EVENTS, events_to_permissions) do
        integration.install_on(
          @org,
          repositories: [],
          installer: @org.admins.first,
          entry_point: :test_case
        )
      end

      Integration::Events.stub_const(:RESOURCE_TO_EVENTS, { "members" => %w(event_test_with_overides) }) do
        event = WithOverridesEvent.new target_repository: nil, target_organization: @org

        assert_includes event.subscribed_hooks, integration_hook
      end
    end

    test "does not inclues integration hooks for suspended installation on the target org for an org-only based event" do
      integration = Integration::Events.stub_const(:SUPPORTED_EVENTS, %w(event_test_with_overides)) do
        Integration::Events.stub_const(:RESOURCE_TO_EVENTS, { "members" => %w(event_test_with_overides) }) do
          create(:integration, :with_active_hook, default_events: %w(event_test_with_overides), default_permissions: { "members" => :read })
        end
      end
      integration_hook = integration.hook

      events_to_permissions = {
        "members" => %w(event_test_with_overides),
      }

      Integration::Events.stub_const(:RESOURCE_TO_EVENTS, events_to_permissions) do
        result = integration.install_on(@org, repositories: [], installer: @org.admins.first, entry_point: :test_case)
        result.installation.suspend!
      end

      Integration::Events.stub_const(:RESOURCE_TO_EVENTS, { "members" => %w(event_test_with_overides) }) do
        event = WithOverridesEvent.new target_repository: nil, target_organization: @org

        refute_includes event.subscribed_hooks, integration_hook
      end
    end

    test "does not include integration hooks for suspended integration" do
      integration = Integration::Events.stub_const(:SUPPORTED_EVENTS, %w(event_test_with_overides)) do
        Integration::Events.stub_const(:RESOURCE_TO_EVENTS, { "members" => %w(event_test_with_overides) }) do
          create(:integration, :with_active_hook, default_events: %w(event_test_with_overides), default_permissions: { "members" => :read })
        end
      end
      integration_hook = integration.hook

      events_to_permissions = {
        "members" => %w(event_test_with_overides),
      }

      Integration::Events.stub_const(:RESOURCE_TO_EVENTS, events_to_permissions) do
        integration.install_on(@org, repositories: [], installer: @org.admins.first, entry_point: :test_case)
      end

      integration.suspend(actor: create(:staff_admin_user), reason: "test")

      Integration::Events.stub_const(:RESOURCE_TO_EVENTS, { "members" => %w(event_test_with_overides) }) do
        event = WithOverridesEvent.new target_repository: nil, target_organization: @org

        refute_includes event.subscribed_hooks, integration_hook
      end
    end

    test "does not include integration hooks for integrations installed on the target org for a repo-only event" do
      events_to_permissions = {
        "metadata" => %w(event_test),                 # a repo-only event
      }

      event_types = events_to_permissions.values.flatten

      integration = Integration::Events.stub_const(:SUPPORTED_EVENTS, event_types) do
        Integration::Events.stub_const(:RESOURCE_TO_EVENTS, events_to_permissions) do
          create(:integration, :with_active_hook, default_events: event_types, default_permissions: { "metadata" => :read, "members" => :read })
        end
      end
      integration_hook = integration.hook

      # Install on @org with 'event_test' event, and permissions on the org, on a specific repo
      @other_org_repo = create(:repository, owner: @org, created_by_user_id: @user.id)
      Integration::Events.stub_const(:RESOURCE_TO_EVENTS, events_to_permissions) do
        integration.install_on(
          @org,
          repositories: [@other_org_repo],
          installer: @org.admins.first,
          entry_point: :test_case
        )
      end

      # Install on another org with 'event_test' event, without permissions on the org,
      @other_org = create(:organization)
      Integration::Events.stub_const(:RESOURCE_TO_EVENTS, events_to_permissions) do
        integration.install_on(
          @other_org,
          repositories: [create(:repository, owner: @other_org, created_by_user_id: @user.id)],
          installer: @other_org.admins.first,
          entry_point: :test_case
        )
      end

      Integration::Events.stub_const(:RESOURCE_TO_EVENTS, events_to_permissions) do
        # Trigger a repo-based event on a repo that the integration is NOT installed on
        # even though it has access to that repo's org.
        event = EventTestEvent.new target_repository: @org_repo, target_organization: @org

        refute_includes event.subscribed_hooks, integration_hook
      end
    end

    test "includes hooks for marketplace listings" do
      listing = create(:marketplace_listing)
      listing_hook = create :hook, :web, events: %w(*), installation_target: listing
      event = WithOverridesEvent.new target_marketplace_listing: listing

      assert_includes event.subscribed_hooks, listing_hook
    end

    test "includes hooks for businesses" do
      event = WithOverridesEvent.new target_organization: @business_org

      assert_same_elements [@business_org_hook, @business_hook], event.subscribed_hooks
    end

    test "sends timing metrics for subscribed hooks methods calls" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      event = WithOverridesEvent.new target_repository: @org_repo, target_organization: @org
      event.subscribed_hooks
      %w[subscribed_integrator_hooks subscribed_integration_hooks
       subscribed_hooks subscribed_hooks_for_repository
       subscribed_hooks_for_organization].each do |func|
        actual_metrics = GitHub.dogstats.distributions("hooks.subscribed_hooks.duration", tags: ["function:#{func}"])
        assert actual_metrics.length > 0
      end
    end
  end

  context "#payload" do
    test "initializes the appropriate payload class for the event" do
      event = EventTestEvent.new

      assert event.payload.instance_of?(Hook::Payload::EventTestPayload)
    end

    test "initializes the payload with the event itself" do
      event = EventTestEvent.new

      assert_equal event, event.payload.hook_event
    end
  end

  context "#to_payload_hash" do
    test "delegates the actual payload building to the payload" do
      event = EventTestEvent.new
      event.payload.expects(:to_hash)

      event.to_payload_hash
    end
  end

  context "#subscribed_installations_for" do
    test "returns the installations subscribed to the given event type (optionally on the target account) for the given Integration" do
      events_to_permissions = {
        "metadata" => %w(event_test_with_overides),
      }

      Integration::Events.stub_const(:RESOURCE_TO_EVENTS, events_to_permissions) do
        @installation = @integration.install_on(
          @org,
          repositories: [],
          installer: @org.admins.first,
          entry_point: :test_case
        ).installation
      end

      Integration::Events.stub_const(:SUPPORTED_EVENTS, %w(event_test_with_overides)) do
        Integration::Events.stub_const(:RESOURCE_TO_EVENTS, { "metadata" => %w(event_test_with_overides) }) do
          create(:integration, :with_active_hook, default_permissions: { "metadata" => :read }, default_events: %w(event_test_with_overides))
        end
      end

      event = WithOverridesEvent.new target_repository: @org_repo, target_organization: @org
      assert_includes event.subscribed_installations_for(@integration), @installation
    end

    test "returns empty Array if there are no installations for the given event type on the target for the given Integration" do
      events_to_permissions = {
        "metadata" => %w(event_test_with_overides),
      }

      other_org = create(:organization)
      Integration::Events.stub_const(:RESOURCE_TO_EVENTS, events_to_permissions) do
        @installation = @integration.install_on(
          other_org,
          repositories: [],
          installer: other_org.admins.first,
          entry_point: :test_case
        ).installation
      end

      event = WithOverridesEvent.new target_repository: @org_repo, target_organization: @org

      assert_empty event.subscribed_installations_for(@integration)
    end

    test "returns an empty Array if there is no target" do
      events_to_permissions = {
        "metadata" => %w(event_test_with_overides),
      }

      Integration::Events.stub_const(:SUPPORTED_EVENTS, %w(event_test_with_overides)) do
        Integration::Events.stub_const(:RESOURCE_TO_EVENTS, events_to_permissions) do
          @installation = make_integration_installation(integration: @integration, target: @org)
        end
      end

      event = WithOverridesEvent.new target_repository: nil, target_organization: nil

      assert_empty event.subscribed_installations_for(@integration)
    end

    test "returns an empty Installation relation when the integration is suspended" do
      events_to_permissions = {
        "metadata" => %w(event_test_with_overides),
      }

      Integration::Events.stub_const(:RESOURCE_TO_EVENTS, events_to_permissions) do
        @installation = @integration.install_on(
          @org,
          repositories: [],
          installer: @org.admins.first,
          entry_point: :test_case
        ).installation
      end

      Integration::Events.stub_const(:SUPPORTED_EVENTS, %w(event_test_with_overides)) do
        Integration::Events.stub_const(:RESOURCE_TO_EVENTS, { "metadata" => %w(event_test_with_overides) }) do
          create(:integration, :with_active_hook, default_permissions: { "metadata" => :read }, default_events: %w(event_test_with_overides))
        end
      end

      @integration.suspend(actor: create(:staff_admin_user), reason: "test")

      event = WithOverridesEvent.new target_repository: @org_repo, target_organization: @org
      assert_equal IntegrationInstallation.none, event.subscribed_installations_for(@integration)
    end

    test "filters out suspended installations" do
      events_to_permissions = {
        "metadata" => %w(event_test_with_overides),
      }

      Integration::Events.stub_const(:RESOURCE_TO_EVENTS, events_to_permissions) do
        @installation = @integration.install_on(@org, repositories: [], installer: @org.admins.first, entry_point: :test_case).installation
        @installation.suspend!
      end

      Integration::Events.stub_const(:SUPPORTED_EVENTS, %w(event_test_with_overides)) do
        Integration::Events.stub_const(:RESOURCE_TO_EVENTS, { "metadata" => %w(event_test_with_overides) }) do
          create(:integration, :with_active_hook, default_permissions: { "metadata" => :read }, default_events: %w(event_test_with_overides))
        end
      end

      event = WithOverridesEvent.new target_repository: @org_repo, target_organization: @org
      refute_includes event.subscribed_installations_for(@integration), @installation
    end
  end

  context "filterable_for_actions?" do
    test "filterable_for_actions? returns false when target_repository is nil" do
      event = EventTestEvent.new target_repository: nil

      refute event.filterable_for_actions?
    end

    test "filterable_for_actions? returns false for non-default branch events" do
      event = EventTestWithTypeEvent.new target_repository: @user_repo, event_type: "push"

      refute event.filterable_for_actions?
    end

    test "filterable_for_actions? returns true for default branch events" do
      event = EventTestWithTypeEvent.new target_repository: @user_repo, event_type: "gollum"

      assert event.filterable_for_actions?
    end
  end

  context "#serialize_primary_resource" do
    test "sets primary_resource_data on the event when primary resource is present" do
      event = Hook::Event::EventTestEvent.new
      assert_nil T.unsafe(event).primary_resource_data
      event.serialize_primary_resource(@user_repo.attributes)
      assert_equal @user_repo.as_json(root: false, dangerously_allow_all_keys: true), T.unsafe(event).primary_resource_data
    end

    test "does not set primary_resource_data on the event when primary resource is nil" do
      event = Hook::Event::EventTestEvent.new
      assert_nil T.unsafe(event).primary_resource_data
      event.serialize_primary_resource(nil)
      assert_nil T.unsafe(event).primary_resource_data
    end
  end

  context "#initialize_primary_resource" do
    test "returns false if primary_resource_data is not set" do
      event = Hook::Event::EventTestEvent.new
      assert_nil T.unsafe(event).primary_resource_data
      assert_equal false, event.initialize_primary_resource
    end

    test "returns true if FF is enabled for the event" do
      event = Hook::Event::EventTestEvent.new
      T.unsafe(event).primary_resource_data = create(:label, repository: @user_repo).as_json(root: false, dangerously_allow_all_keys: true)
      enable_feature_flag(:prehydrate_primary_webhook_data_for_event_test, @user_repo)

      assert_equal true, event.initialize_primary_resource
    end

    test "returns false if FF is NOT enabled" do
      disable_feature_flag(:prehydrate_primary_webhook_data_for_event_test)
      event = Hook::Event::EventTestEvent.new

      T.unsafe(event).primary_resource_data = create(:label, repository: @user_repo).as_json(root: false, dangerously_allow_all_keys: true)

      assert_equal false, event.initialize_primary_resource
    end
  end

  context "#record_query_counts" do
    test "records query per db counts for block" do
      GitHub::MysqlInstrumenter.with_instrument_and_track do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
        event = Hook::Event::EventTestEvent.new

        event.record_query_counts("foo") do
          Repository.find_by(id: @user_repo.id)
        end

        actual_metrics = GitHub.dogstats.distributions("hook.event.foo")
        assert_equal 1, actual_metrics.length

        actual_metric = actual_metrics.first
        assert_equal 1, actual_metric.value

        actual_tags = actual_metric.tags
        assert actual_tags.any? { |tag| tag.include?("cluster:") }
      end
    end

    test "records a query count even if there are no queries" do
      GitHub::MysqlInstrumenter.with_instrument_and_track do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
        event = Hook::Event::EventTestEvent.new

        event.record_query_counts("foo") do
          Repository.new(id: 1)
        end

        actual_metrics = GitHub.dogstats.distributions("hook.event.foo")
        assert_equal 1, actual_metrics.length

        actual_metric = actual_metrics.first
        assert_equal 0, actual_metric.value

        actual_tags = actual_metric.tags
        refute actual_tags.any? { |tag| tag.include?("cluster:") }
      end
    end

    test "records n+1 query for block" do
      GitHub::MysqlInstrumenter.with_instrument_and_track do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
        event = Hook::Event::EventTestEvent.new

        event.record_query_counts("foo", true) do
          Repository.find_by(id: @user_repo.id)
          Repository.find_by(id: @repo.id)
        end

        actual_metrics = GitHub.dogstats.distributions("hook.event.foo.nplusone")
        assert_equal 1, actual_metrics.length

        actual_metric = actual_metrics.first
        assert_equal 1, actual_metric.value
      end
    end

    test "records 0 n+1 queries for block" do
      GitHub::MysqlInstrumenter.reset_stats
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      event = Hook::Event::EventTestEvent.new

      event.record_query_counts("foo", true) do
        Repository.find_by(id: @user_repo.id)
      end

      actual_metrics = GitHub.dogstats.distributions("hook.event.foo.nplusone")
      assert_equal 1, actual_metrics.length

      actual_metric = actual_metrics.first
      assert_equal 0, actual_metric.value
    end

    test "records 0 n+1 queries for block if no queries" do
      GitHub::MysqlInstrumenter.reset_stats
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      event = Hook::Event::EventTestEvent.new

      event.record_query_counts("foo", true) do
        # no-op
      end

      actual_metrics = GitHub.dogstats.distributions("hook.event.foo.nplusone")
      assert_equal 1, actual_metrics.length

      actual_metric = actual_metrics.first
      assert_equal 0, actual_metric.value
    end

    test "does not track n+1 queries for block if track_n_plus_one is disabled" do
      GitHub::MysqlInstrumenter.reset_stats
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      event = Hook::Event::EventTestEvent.new

      event.record_query_counts("foo", false) do
        Repository.find_by(id: @user_repo.id)
        Repository.find_by(id: @repo.id)
      end

      actual_metrics = GitHub.dogstats.distributions("hook.event.foo.nplusone")
      assert_equal 0, actual_metrics.length
    end
  end

  context "#initialize" do
    test "sets the attributes" do
      attrs = { foo: :bar }
      event = Hook::Event::EventTestEvent.new(attrs)
      assert attrs <= event.attributes
    end

    test "sets triggered_at" do
      event = Hook::Event::EventTestEvent.new
      refute_nil T.unsafe(event).triggered_at
    end

    test "sets primary_resource_data" do
      enable_feature_flag(:prehydrate_primary_webhook_data_for_event_test)
      event = Hook::Event::EventTestEvent.new(primary_resource: @user_repo.attributes)
      refute_nil T.unsafe(event).primary_resource_data
    end

    test "initializes the primary resource" do
      Hook::Event::EventTestEvent.any_instance.expects(:initialize_primary_resource).once
      Hook::Event::EventTestEvent.new
    end
  end

  context "#prehydrate_primary_webhook_data_enabled?" do
    test "returns true when FF is enabled for a repo and a hash with repo_id is passed in" do
      enable_feature_flag(:prehydrate_primary_webhook_data_for_event_test, @user_repo)
      event = Hook::Event::EventTestEvent.new
      assert event.prehydrate_primary_webhook_data_enabled?("repository_id" => @user_repo.id)
    end

    test "returns true when FF is enabled for a repo and an object that responds to repo_id is passed in" do
      enable_feature_flag(:prehydrate_primary_webhook_data_for_event_test, @user_repo)
      event = Hook::Event::EventTestEvent.new
      assert event.prehydrate_primary_webhook_data_enabled?(CheckRun.instantiate("repository_id" => @user_repo.id))
    end

    test "returns true when FF is fully enabled" do
      enable_feature_flag(:prehydrate_primary_webhook_data_for_event_test)
      event = Hook::Event::EventTestEvent.new
      assert event.prehydrate_primary_webhook_data_enabled?(nil)
    end

    test "returns false when repo is enabled but not passed in" do
      enable_feature_flag(:prehydrate_primary_webhook_data_for_event_test, @user_repo)
      event = Hook::Event::EventTestEvent.new
      refute event.prehydrate_primary_webhook_data_enabled?(nil)
    end
  end
end
