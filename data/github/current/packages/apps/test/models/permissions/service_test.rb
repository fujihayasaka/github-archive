# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

class PermissionsServiceTest < GitHub::TestCase
  include PermissionsHelper
  include DogstatsTestHelpers
  include GitHub::LoggerHelper
  include HydroTestHelpers

  fixtures do
    @integration = create(:integration)
    @user = create(:user)
  end

  context "EntryPoint.build" do
    test "ensure nil entry_points are treated as unknown" do
      entry_point = Permissions::Service::EntryPoint.build(nil)
      assert_equal :unknown, entry_point.entry_point
    end
  end

  context "EntryPoint.instrument" do
    test "does not publish to hydro when rows are empty" do
      GitHub.flipper[:permissions_service_actor_level_metrics].enable

      Permissions::Service::EntryPoint.instrument(
        metric_suffix: "insert_rows_requested",
        entry_point: :test_case,
        rows: [],
      )

      assert_dogstats_increment(
        "permissions_service.instrumentation.no_actor_context",
        tags: ["entry_point:test_case", "metric_suffix:insert_rows_requested"],
      )
      refute_hydro_messages(schema: "github.permissions.v0.Created")
    end
  end

  context ".grant_permissions" do
    test "grants permission" do
      refute_granted_in_permissions_table(actor_id: @user.id, subject_id: @integration.id, subject_type: "SomeTestSubjectType")

      row = [
        @user.id,
        "User",
        Ability.actions[:admin],
        @integration.id,
        "SomeTestSubjectType",
        Ability.priorities[:direct],
        0,
        GitHub::SQL::ArelLiterals::NOW,
        GitHub::SQL::ArelLiterals::NOW,
        nil,
      ]

      Permissions::Service.grant_permissions([row], entry_point: :test_case)
      assert_granted_in_permissions_table(actor_id: @user.id, subject_id: @integration.id, subject_type: "SomeTestSubjectType")
    end

    test "instruments one requested row to insert to datadog" do
      assert_dogstats_distribution(0, "permissions_service.insert_rows_requested")
      row = [
        @user.id,
        "User",
        Ability.actions[:admin],
        @integration.id,
        "SomeTestSubjectType",
        Ability.priorities[:direct],
        0,
        GitHub::SQL::ArelLiterals::NOW,
        GitHub::SQL::ArelLiterals::NOW,
        nil,
      ]

      Permissions::Service.grant_permissions([row], entry_point: :test_case)
      assert_dogstats_distribution(1, "permissions_service.insert_rows_requested", tags: ["entry_point:test_case"])
    end

    test "instruments multiple requested rows to insert" do
      assert_dogstats_distribution(0, "permissions_service.insert_rows_requested")
      rows = [
        [
          @user.id,
          "User",
          Ability.actions[:admin],
          @integration.id,
          "SomeTestSubjectType",
          Ability.priorities[:direct],
          0,
          GitHub::SQL::ArelLiterals::NOW,
          GitHub::SQL::ArelLiterals::NOW,
          nil,
        ],
        [
          @user.id,
          "User",
          Ability.actions[:admin],
          @integration.id,
          "SomeOtherTestSubjectType",
          Ability.priorities[:direct],
          0,
          GitHub::SQL::ArelLiterals::NOW,
          GitHub::SQL::ArelLiterals::NOW,
          nil,
        ]
      ]

      Permissions::Service.grant_permissions(rows, entry_point: :test_case)
      assert_dogstats_distribution(1, "permissions_service.insert_rows_requested", tags: ["entry_point:test_case"])
      assert_dogstats_distribution_value(2, "permissions_service.insert_rows_requested")
    end

    test "instruments number of requested rows and tags known entry point" do
      assert_dogstats_distribution(0, "permissions_service.insert_rows_requested")
      row = [
        @user.id,
        "User",
        Ability.actions[:admin],
        @integration.id,
        "SomeTestSubjectType",
        Ability.priorities[:direct],
        0,
        GitHub::SQL::ArelLiterals::NOW,
        GitHub::SQL::ArelLiterals::NOW,
        nil,
      ]

      Permissions::Service.grant_permissions([row], entry_point: :test_case)
      assert_dogstats_distribution(1, "permissions_service.insert_rows_requested", tags: ["entry_point:test_case"])
    end

    context "hydro metrics instrumentation" do
      test "publishes one requested row to insert to hydro when the feature and entry_point are enabled" do
        GitHub.flipper[:permissions_service_actor_level_metrics].enable

        row = [
          @user.id,
          "User",
          Ability.actions[:admin],
          @integration.id,
          "SomeTestSubjectType",
          Ability.priorities[:direct],
          0,
          GitHub::SQL::ArelLiterals::NOW,
          GitHub::SQL::ArelLiterals::NOW,
          nil,
        ]

        Permissions::Service.grant_permissions([row], entry_point: :rest_api_integrations_create_installation_access_token)

        expected_message = {
          entry_point: "rest_api_integrations_create_installation_access_token",
          actor_id: @user.id,
          actor_type: :ACTOR_TYPE_USER,
          target_type: :TARGET_TYPE_UNKNOWN,
          owner_type: :ACTOR_OWNER_TYPE_UNKNOWN,
          total: 1,
          subject_type_total: {
            "SomeTestSubjectType" => 1,
          },
          write_type: :WRITE_TYPE_CREATE,
          digest: digest_from_normalized_rows([row]),
        }
        assert_hydro_published(expected_message, schema: "github.permissions.v0.Created")
      end

      test "publishes actor level metrics to hydro" do
        GitHub.flipper[:permissions_service_actor_level_metrics].enable

        installation = make_integration_installation(
          target: @user, integration: @integration,
        )
        scoped_installation = make_scoped_integration_installation(parent: installation)

        row = [
          scoped_installation.id,
          "ScopedIntegrationInstallation",
          Ability.actions[:admin],
          @integration.id,
          "SomeTestSubjectType",
          Ability.priorities[:direct],
          0,
          GitHub::SQL::ArelLiterals::NOW,
          GitHub::SQL::ArelLiterals::NOW,
          nil,
        ]

        entry_point = Permissions::Service::EntryPoint.build(
          :rest_api_integrations_create_installation_access_token,
          target: @user,
          parent_installation: installation,
          actor_owner: @integration,
        )

        Permissions::Service.grant_permissions([row], entry_point: entry_point)

        expected_message = {
          entry_point: "rest_api_integrations_create_installation_access_token",
          total: 1,
          actor_id: scoped_installation.id,
          actor_type: :ACTOR_TYPE_SCOPED_INTEGRATION_INSTALLATION,
          target_id: @user.id,
          target_type: :TARGET_TYPE_USER,
          owner_id: @integration.id,
          owner_type: :ACTOR_OWNER_TYPE_INTEGRATION,
          owner_name: @integration.name,
          parent_installation_id: installation.id,
          subject_type_total: {
            "SomeTestSubjectType" => 1,
          },
          write_type: :WRITE_TYPE_CREATE,
          digest: digest_from_normalized_rows([row]),
        }
        assert_hydro_published(expected_message, schema: "github.permissions.v0.Created")
      end

      test "publishes multiple requested rows to insert to hydro" do
        GitHub.flipper[:permissions_service_actor_level_metrics].enable

        rows = [
          [
            @user.id,
            "User",
            Ability.actions[:admin],
            @integration.id,
            "SomeTestSubjectType",
            Ability.priorities[:direct],
            0,
            GitHub::SQL::ArelLiterals::NOW,
            GitHub::SQL::ArelLiterals::NOW,
            nil,
          ],
          [
            @user.id,
            "User",
            Ability.actions[:admin],
            @integration.id,
            "SomeOtherTestSubjectType",
            Ability.priorities[:direct],
            0,
            GitHub::SQL::ArelLiterals::NOW,
            GitHub::SQL::ArelLiterals::NOW,
            nil,
          ],
          [
            @user.id,
            "User",
            Ability.actions[:admin],
            @integration.id,
            "SomeOtherTestSubjectType",
            Ability.priorities[:direct],
            0,
            GitHub::SQL::ArelLiterals::NOW,
            GitHub::SQL::ArelLiterals::NOW,
            nil,
          ],
        ]

        Permissions::Service.grant_permissions(rows, entry_point: :rest_api_integrations_create_installation_access_token)

        expected_message = {
          entry_point: "rest_api_integrations_create_installation_access_token",
          actor_id: @user.id,
          actor_type: :ACTOR_TYPE_USER,
          target_type: :TARGET_TYPE_UNKNOWN,
          owner_type: :ACTOR_OWNER_TYPE_UNKNOWN,
          total: 3,
          subject_type_total: {
            "SomeTestSubjectType" => 1,
            "SomeOtherTestSubjectType" => 2,
          },
          write_type: :WRITE_TYPE_CREATE,
          digest: digest_from_normalized_rows(rows),
        }
        assert_hydro_published(expected_message, schema: "github.permissions.v0.Created")
      end

      test "does not publish to hydro when the feature is disabled" do
        GitHub.flipper[:permissions_service_actor_level_metrics].disable

        row = [
          @user.id,
          "User",
          Ability.actions[:admin],
          @integration.id,
          "SomeTestSubjectType",
          Ability.priorities[:direct],
          0,
          GitHub::SQL::ArelLiterals::NOW,
          GitHub::SQL::ArelLiterals::NOW,
          nil,
        ]

        Permissions::Service.grant_permissions([row], entry_point: :rest_api_integrations_create_installation_access_token)
        refute_hydro_messages(schema: "github.permissions.v0.Created")
      end
    end

    test "explodes if an unregistered entry point is provided" do
      row = [
        @user.id,
        "User",
        Ability.actions[:admin],
        @integration.id,
        "SomeTestSubjectType",
        Ability.priorities[:direct],
        0,
        GitHub::SQL::ArelLiterals::NOW,
        GitHub::SQL::ArelLiterals::NOW,
        nil,
      ]

      assert_raises(Permissions::Service::EntryPoint::UnregisteredEntryPointError) do
        Permissions::Service.grant_permissions([row], entry_point: :some_unregistered_entry_point)
      end
    end

    test "does not explode if a 'nil' entry point is provided" do
      row = [
        @user.id,
        "User",
        Ability.actions[:admin],
        @integration.id,
        "SomeTestSubjectType",
        Ability.priorities[:direct],
        0,
        GitHub::SQL::ArelLiterals::NOW,
        GitHub::SQL::ArelLiterals::NOW,
        nil,
      ]

      Permissions::Service.grant_permissions([row], entry_point: nil)
      assert_dogstats_distribution(1, "permissions_service.insert_rows_requested", tags: ["entry_point:unknown"])
    end

    test "does not explode in production if entry point is not registered" do
      row = [
        @user.id,
        "User",
        Ability.actions[:admin],
        @integration.id,
        "SomeTestSubjectType",
        Ability.priorities[:direct],
        0,
        GitHub::SQL::ArelLiterals::NOW,
        GitHub::SQL::ArelLiterals::NOW,
        nil,
      ]

      GitHub::AppEnvironment.stubs(:production?).returns(true)

      Permissions::Service.grant_permissions([row], entry_point: :some_unregistered_entry_point)
      assert_dogstats_distribution(1, "permissions_service.insert_rows_requested", tags: ["entry_point:unknown"])

      # Failbot no-ops in enterprise, but the rest of the test if valid
      unless GitHub.enterprise?
        assert_equal "Permissions::Service::EntryPoint::UnregisteredEntryPointError", Failbot.reports&.last&.dig("exception_detail", 0, "type")
      end
    end
  end

  context ".grant_permissions!" do
    test "grants permission" do
      refute_granted_in_permissions_table(actor_id: @user.id, subject_id: @integration.id, subject_type: "SomeTestSubjectType")
      timestamp = Time.zone.now

      row = {
        actor_id: @user.id,
        actor_type: "User",
        action: Ability.actions[:admin],
        subject_id: @integration.id,
        subject_type: "SomeTestSubjectType",
        priority: Ability.priorities[:direct],
        parent_id: 0,
        created_at: timestamp,
        updated_at: timestamp,
        expires_at: nil,
      }

      Permissions::Service.grant_permissions!([row], entry_point: :test_case)
      assert_granted_in_permissions_table(actor_id: @user.id, subject_id: @integration.id, subject_type: "SomeTestSubjectType")
    end
  end

  context ".update_action_for_permissions" do
    test "updates the action for an actor an a set of subject_types" do
      rows = [
        [@user.id, "User", Ability.actions[:read], @integration.id, "SomeTestSubjectType",      Ability.priorities[:direct], 0, GitHub::SQL::ArelLiterals::NOW, GitHub::SQL::ArelLiterals::NOW, nil],
        [@user.id, "User", Ability.actions[:read], @integration.id, "SomeOtherTestSubjectType", Ability.priorities[:direct], 0, GitHub::SQL::ArelLiterals::NOW, GitHub::SQL::ArelLiterals::NOW, nil],
      ]

      Permissions::Service.grant_permissions(rows, entry_point: :test_case)

      assert_granted_in_permissions_table(actor_id: @user.id, subject_id: @integration.id, subject_type: "SomeTestSubjectType",      action: :read)
      assert_granted_in_permissions_table(actor_id: @user.id, subject_id: @integration.id, subject_type: "SomeOtherTestSubjectType", action: :read)

      Permissions::Service.update_action_for_permissions(actor_ids: [@user.id], actor_type: "User", subject_types: ["SomeTestSubjectType"], action: :write)

      assert_granted_in_permissions_table(actor_id: @user.id, subject_id: @integration.id, subject_type: "SomeTestSubjectType",      action: :write)
      assert_granted_in_permissions_table(actor_id: @user.id, subject_id: @integration.id, subject_type: "SomeOtherTestSubjectType", action: :read)
    end
  end

  context ".update_expires_at_for_permissions" do
    test "instruments one requested row to be updated" do
      rows = [
        [@user.id, "User", Ability.actions[:read], @integration.id, "SomeTestSubjectType",      Ability.priorities[:direct], 0, GitHub::SQL::ArelLiterals::NOW, GitHub::SQL::ArelLiterals::NOW, nil]
      ]

      Permissions::Service.grant_permissions(rows, entry_point: :test_case)

      assert_granted_in_permissions_table(actor_id: @user.id, subject_id: @integration.id, subject_type: "SomeTestSubjectType", action: :read)
      permission = Permission.find_by!(actor: @user, subject_id: @integration.id, subject_type: "SomeTestSubjectType", action: :read)

      assert_dogstats_distribution(0, "permissions_service.update_rows_requested")

      Permissions::Service.update_expires_at_for_permissions(permission_ids: [permission.id], timestamp: Time.now, entry_point: :test_case)
      assert_dogstats_distribution(1, "permissions_service.update_rows_requested", tags: ["entry_point:test_case"])
    end
  end

  context ".revoke_permissions" do
    test "revokes permissions" do
      row = [
        @user.id,
        "User",
        Ability.actions[:admin],
        @integration.id,
        "SomeTestSubjectType",
        Ability.priorities[:direct],
        0,
        GitHub::SQL::ArelLiterals::NOW,
        GitHub::SQL::ArelLiterals::NOW,
        nil,
      ]

      Permissions::Service.grant_permissions([row], entry_point: :test_case)
      assert_granted_in_permissions_table(actor_id: @user.id, subject_id: @integration.id, subject_type: "SomeTestSubjectType")

      Permissions::Service.revoke_permissions(
        actor_id: @user.id,
        actor_type: "User",
        subject_id: @integration.id,
        subject_type: "SomeTestSubjectType",
        action: Ability.actions[:admin],
        priority: Ability.priorities[:direct],
      )

      refute_granted_in_permissions_table(actor_id: @user.id, subject_id: @integration.id, subject_type: "SomeTestSubjectType")
    end

    test "instruments when a row is deleted" do
      assert_dogstats_distribution(0, "permissions_service.deleted_rows")

      grant_direct_permission(actor: @user, subject: @user, subject_type: "Irrelevant", action: :admin)

      Permissions::Service.revoke_permissions(
        actor_id: @user.id,
        actor_type: "User",
        subject_id: @user.id,
        subject_type: "Irrelevant",
        action: Ability.actions[:admin],
        priority: Ability.priorities[:direct],
        entry_point: :test_case
      )
      assert_dogstats_distribution(1, "permissions_service.deleted_rows", tags: ["entry_point:test_case"])
    end

    test "instruments actor context" do
      GitHub.flipper[:permissions_service_actor_level_metrics].enable
      Permissions::EntryPoint::ActorContext.stubs(:digest_from_rows).returns("fake-digest")

      grant_direct_permission(actor: @user, subject: @user, subject_type: "Irrelevant", action: :admin)

      Permissions::Service.revoke_permissions(
        actor_id: @user.id,
        actor_type: "User",
        subject_id: @user.id,
        subject_type: "Irrelevant",
        action: Ability.actions[:admin],
        priority: Ability.priorities[:direct],
        entry_point: :test_case
      )

      expected_message = {
        entry_point: "test_case",
        actor_id: @user.id,
        actor_type: :ACTOR_TYPE_USER,
        target_type: :TARGET_TYPE_UNKNOWN,
        owner_type: :ACTOR_OWNER_TYPE_UNKNOWN,
        total: 1,
        subject_type_total: {
          "Irrelevant" => 1,
        },
        write_type: :WRITE_TYPE_DELETE,
        digest: "fake-digest",
      }
      assert_hydro_published(expected_message, schema: "github.permissions.v0.Created")
      assert_dogstats_distribution("permissions.service.actor_context_query", tags: ["entry_point:test_case", "background:true"])
    end

    test "instruments as entry_point unknown when nil is provided" do
      assert_dogstats_distribution(0, "permissions_service.deleted_rows")

      grant_direct_permission(actor: @user, subject: @user, subject_type: "Irrelevant", action: :admin)

      Permissions::Service.revoke_permissions(
        actor_id: @user.id,
        actor_type: "User",
        subject_id: @user.id,
        subject_type: "Irrelevant",
        action: Ability.actions[:admin],
        priority: Ability.priorities[:direct],
        entry_point: nil
      )
      assert_dogstats_distribution(1, "permissions_service.deleted_rows", tags: ["entry_point:unknown"])
    end
  end

  context ".revoke_permissions_granted_on_actor{s}" do
    test "revokes permissions granted on an actor" do
      row = [
        @user.id,
        "User",
        Ability.actions[:admin],
        @integration.id,
        "SomeTestSubjectType",
        Ability.priorities[:direct],
        0,
        GitHub::SQL::ArelLiterals::NOW,
        GitHub::SQL::ArelLiterals::NOW,
        nil,
      ]

      Permissions::Service.grant_permissions([row], entry_point: :test_case)
      assert_granted_in_permissions_table(actor_id: @user.id, subject_id: @integration.id, subject_type: "SomeTestSubjectType")

      Permissions::Service.revoke_permissions_granted_on_actor(actor_id: @user.id, actor_type: "User")

      refute_granted_in_permissions_table(actor_id: @user.id, subject_id: @integration.id, subject_type: "SomeTestSubjectType")
    end

    test "can filter by subject_types" do
      rows = [
        [@user.id, "User", Ability.actions[:admin], @integration.id, "SomeTestSubjectType",      Ability.priorities[:direct], 0, GitHub::SQL::ArelLiterals::NOW, GitHub::SQL::ArelLiterals::NOW, nil],
        [@user.id, "User", Ability.actions[:admin], @integration.id, "SomeOtherTestSubjectType", Ability.priorities[:direct], 0, GitHub::SQL::ArelLiterals::NOW, GitHub::SQL::ArelLiterals::NOW, nil],
      ]

      Permissions::Service.grant_permissions(rows, entry_point: :test_case)

      assert_granted_in_permissions_table(actor_id: @user.id, subject_id: @integration.id, subject_type: "SomeTestSubjectType")
      assert_granted_in_permissions_table(actor_id: @user.id, subject_id: @integration.id, subject_type: "SomeOtherTestSubjectType")

      Permissions::Service.revoke_permissions_granted_on_actor(actor_id: @user.id, actor_type: "User", subject_types: ["SomeTestSubjectType"])

      refute_granted_in_permissions_table(actor_id: @user.id, subject_id: @integration.id, subject_type: "SomeTestSubjectType")
      assert_granted_in_permissions_table(actor_id: @user.id, subject_id: @integration.id, subject_type: "SomeOtherTestSubjectType")
    end

    test "instruments when a row is deleted" do
      assert_dogstats_distribution(0, "permissions_service.deleted_rows")

      grant_direct_permission(actor: @user, subject: @user, subject_type: "Irrelevant", action: :admin)

      Permissions::Service.revoke_permissions_granted_on_actor(
        actor_id: @user.id,
        actor_type: "User",
        subject_types: ["Irrelevant"],
        entry_point: :test_case
      )
      assert_dogstats_distribution(1, "permissions_service.deleted_rows", tags: ["entry_point:test_case"])
    end

    test "instruments actor context" do
      GitHub.flipper[:permissions_service_actor_level_metrics].enable
      Permissions::EntryPoint::ActorContext.stubs(:digest_from_rows).returns("fake-digest")

      grant_direct_permission(
        actor: @user,
        subject: @user,
        subject_type: "Irrelevant",
        action: :admin
      )

      Permissions::Service.revoke_permissions_granted_on_actor(
        actor_id: @user.id,
        actor_type: "User",
        subject_types: ["Irrelevant"],
        entry_point: :test_case
      )

      expected_message = {
        entry_point: "test_case",
        actor_id: @user.id,
        actor_type: :ACTOR_TYPE_USER,
        target_type: :TARGET_TYPE_UNKNOWN,
        owner_type: :ACTOR_OWNER_TYPE_UNKNOWN,
        total: 1,
        subject_type_total: {
          "Irrelevant" => 1,
        },
        write_type: :WRITE_TYPE_DELETE,
        digest: "fake-digest",
      }
      assert_hydro_published(expected_message, schema: "github.permissions.v0.Created")
      assert_dogstats_distribution("permissions.service.actor_context_query", tags: ["entry_point:test_case", "background:true"])
    end

    test "instruments an entry point as unknown when nil is passed" do
      assert_dogstats_distribution(0, "permissions_service.deleted_rows")

      grant_direct_permission(actor: @user, subject: @user, subject_type: "Irrelevant", action: :admin)

      Permissions::Service.revoke_permissions_granted_on_actor(
        actor_id: @user.id,
        actor_type: "User",
        subject_types: ["Irrelevant"],
        entry_point: nil,
      )
      assert_dogstats_distribution(1, "permissions_service.deleted_rows", tags: ["entry_point:unknown"])
    end
  end

  context ".revoke_permissions_granted_on_subject{s}" do
    test "revokes a permissions granted on a subject" do
      row = [
        @user.id,
        "User",
        Ability.actions[:admin],
        @integration.id,
        "SomeTestSubjectType",
        Ability.priorities[:direct],
        0,
        GitHub::SQL::ArelLiterals::NOW,
        GitHub::SQL::ArelLiterals::NOW,
        nil,
      ]

      Permissions::Service.grant_permissions([row], entry_point: :test_case)
      assert_granted_in_permissions_table(actor_id: @user.id, subject_id: @integration.id, subject_type: "SomeTestSubjectType")

      Permissions::Service.revoke_permissions_granted_on_subject(
        subject_id: @integration.id,
        subject_types: ["SomeTestSubjectType"],
        entry_point: :test_case,
      )

      refute_granted_in_permissions_table(actor_id: @user.id, subject_id: @integration.id, subject_type: "SomeTestSubjectType")
    end

    test "instruments actor context" do
      GitHub.flipper[:permissions_service_actor_level_metrics].enable
      Permissions::EntryPoint::ActorContext.stubs(:digest_from_rows).returns("fake-digest")

      row = [
        @user.id,
        "User",
        Ability.actions[:admin],
        @integration.id,
        "SomeTestSubjectType",
        Ability.priorities[:direct],
        0,
        GitHub::SQL::ArelLiterals::NOW,
        GitHub::SQL::ArelLiterals::NOW,
        nil,
      ]

      Permissions::Service.grant_permissions([row], entry_point: :test_case)
      Permissions::Service.revoke_permissions_granted_on_subject(
        subject_id: @integration.id,
        subject_types: ["SomeTestSubjectType"],
        entry_point: :test_case,
      )

      expected_message = {
        entry_point: "test_case",
        actor_id: @user.id,
        actor_type: :ACTOR_TYPE_USER,
        target_type: :TARGET_TYPE_UNKNOWN,
        owner_type: :ACTOR_OWNER_TYPE_UNKNOWN,
        total: 1,
        subject_type_total: {
          "SomeTestSubjectType" => 1,
        },
        write_type: :WRITE_TYPE_DELETE,
        digest: "fake-digest",
      }
      assert_hydro_published(expected_message, schema: "github.permissions.v0.Created")
      assert_dogstats_distribution("permissions.service.actor_context_query", tags: ["entry_point:test_case", "background:true"])
    end

    test "can filter by actor" do
      random_user = create(:user)

      rows = [
        [@user.id,       "User", Ability.actions[:admin], @integration.id, "SomeTestSubjectType", Ability.priorities[:direct], 0, GitHub::SQL::ArelLiterals::NOW, GitHub::SQL::ArelLiterals::NOW, nil],
        [random_user.id, "User", Ability.actions[:admin], @integration.id, "SomeTestSubjectType", Ability.priorities[:direct], 0, GitHub::SQL::ArelLiterals::NOW, GitHub::SQL::ArelLiterals::NOW, nil],
      ]

      Permissions::Service.grant_permissions(rows, entry_point: :test_case)

      assert_granted_in_permissions_table(actor_id: @user.id,       subject_id: @integration.id, subject_type: "SomeTestSubjectType")
      assert_granted_in_permissions_table(actor_id: random_user.id, subject_id: @integration.id, subject_type: "SomeTestSubjectType")

      Permissions::Service.revoke_permissions_granted_on_subject(
        actor_id: @user.id,
        actor_type: "User",
        subject_id: @integration.id,
        subject_types: ["SomeTestSubjectType"],
        entry_point: :test_case,
      )

      refute_granted_in_permissions_table(actor_id: @user.id, subject_id: @integration.id, subject_type: "SomeTestSubjectType")
      assert_granted_in_permissions_table(actor_id: random_user.id, subject_id: @integration.id, subject_type: "SomeTestSubjectType")
    end

    test "instruments when a row is deleted" do
      assert_dogstats_distribution(0, "permissions_service.deleted_rows")

      grant_direct_permission(actor: @user, subject: @user, subject_type: "SomeTestSubjectType", action: :admin)

      Permissions::Service.revoke_permissions_granted_on_subject(
        actor_id: @user.id,
        actor_type: "User",
        subject_id: @user.id,
        subject_types: ["SomeTestSubjectType"],
        entry_point: :test_case
      )
      assert_dogstats_distribution(1, "permissions_service.deleted_rows", tags: ["entry_point:test_case"])
    end

    test "instruments an entry point as unknown when nil is passed" do
      assert_dogstats_distribution(0, "permissions_service.deleted_rows")

      grant_direct_permission(actor: @user, subject: @user, subject_type: "SomeTestSubjectType", action: :admin)

      Permissions::Service.revoke_permissions_granted_on_subject(
        actor_id: @user.id,
        actor_type: "User",
        subject_id: @user.id,
        subject_types: ["SomeTestSubjectType"],
        entry_point: nil
      )
      assert_dogstats_distribution(1, "permissions_service.deleted_rows", tags: ["entry_point:unknown"])
    end
  end

  context ".actor_ids_granted_permission" do
    test "returns a list of actor IDs that have been granted permission on the subject" do
      row = [
        @user.id,
        "User",
        Ability.actions[:admin],
        @integration.id,
        "SomeTestSubjectType",
        Ability.priorities[:direct],
        0,
        GitHub::SQL::ArelLiterals::NOW,
        GitHub::SQL::ArelLiterals::NOW,
        nil,
      ]

      Permissions::Service.grant_permissions([row], entry_point: :test_case)
      assert_granted_in_permissions_table(actor_id: @user.id, subject_id: @integration.id, subject_type: "SomeTestSubjectType")

      actual_actor_ids = Permissions::Service.actor_ids_granted_permission(
        actor_type: "User",
        subject_type: "SomeTestSubjectType",
        subject_ids: [@integration.id],
        action: Ability.actions[:admin],
      )
      assert_includes actual_actor_ids, @user.id
    end
  end

  context ".subject_ids_granted_permission" do
    test "returns the subject IDs an actor has been granted permission on" do
      row = [
        @user.id,
        "User",
        Ability.actions[:admin],
        @integration.id,
        "SomeTestSubjectType",
        Ability.priorities[:direct],
        0,
        GitHub::SQL::ArelLiterals::NOW,
        GitHub::SQL::ArelLiterals::NOW,
        nil,
      ]

      Permissions::Service.grant_permissions([row], entry_point: :test_case)
      assert_granted_in_permissions_table(actor_id: @user.id, subject_id: @integration.id, subject_type: "SomeTestSubjectType")

      actual_subject_ids = Permissions::Service.subject_ids_granted_permission(
        actor_ids: [@user.id],
        actor_type: "User",
        subject_type: "SomeTestSubjectType",
        action: Ability.actions[:admin],
      )
      assert_includes actual_subject_ids, @integration.id
    end

    test "returns the subject IDs multiple actors have been granted permission on" do
      row_one = [
        @user.id,
        "User",
        Ability.actions[:admin],
        @integration.id,
        "SomeTestSubjectType",
        Ability.priorities[:direct],
        0,
        GitHub::SQL::ArelLiterals::NOW,
        GitHub::SQL::ArelLiterals::NOW,
        nil,
      ]
      u = create :user
      row_two = [
        u.id,
        "User",
        Ability.actions[:admin],
        @integration.id,
        "SomeTestSubjectType",
        Ability.priorities[:direct],
        0,
        GitHub::SQL::ArelLiterals::NOW,
        GitHub::SQL::ArelLiterals::NOW,
        nil,
      ]

      Permissions::Service.grant_permissions([row_one], entry_point: :test_case)
      Permissions::Service.grant_permissions([row_two], entry_point: :test_case)
      assert_granted_in_permissions_table(actor_id: @user.id, subject_id: @integration.id, subject_type: "SomeTestSubjectType")
      assert_granted_in_permissions_table(actor_id: u.id, subject_id: @integration.id, subject_type: "SomeTestSubjectType")

      actual_subject_ids = Permissions::Service.subject_ids_granted_permission(
        actor_ids: [@user.id, u.id],
        actor_type: "User",
        subject_type: "SomeTestSubjectType",
        action: Ability.actions[:admin],
      )
      assert_includes actual_subject_ids, @integration.id
    end

    test "returns the subject IDs an actor has been granted permission on when multiple actions are provided" do
      row = [
        @user.id,
        "User",
        Ability.actions[:admin],
        @integration.id,
        "SomeTestSubjectType",
        Ability.priorities[:direct],
        0,
        GitHub::SQL::ArelLiterals::NOW,
        GitHub::SQL::ArelLiterals::NOW,
        nil,
      ]

      Permissions::Service.grant_permissions([row], entry_point: :test_case)
      assert_granted_in_permissions_table(actor_id: @user.id, subject_id: @integration.id, subject_type: "SomeTestSubjectType")

      actual_subject_ids = Permissions::Service.subject_ids_granted_permission(
        actor_ids: [@user.id],
        actor_type: "User",
        subject_type: "SomeTestSubjectType",
        action: [Ability.actions[:admin], Ability.actions[:write]],
      )
      assert_includes actual_subject_ids, @integration.id
    end
  end

  context ".has_direct_permission?" do
    test "returns direct permissions betwen an actor and a given subject" do
      row = [
        @user.id,
        "User",
        Ability.actions[:admin],
        @integration.id,
        "SomeTestSubjectType",
        Ability.priorities[:direct],
        0,
        GitHub::SQL::ArelLiterals::NOW,
        GitHub::SQL::ArelLiterals::NOW,
        nil,
      ]

      Permissions::Service.grant_permissions([row], entry_point: :test_case)
      assert_granted_in_permissions_table(actor_id: @user.id, subject_id: @integration.id, subject_type: "SomeTestSubjectType")

      assert Permissions::Service.has_direct_permission?(
        actor_id: @user.id,
        actor_type: "User",
        subject_type: "SomeTestSubjectType",
        subject_ids: [@integration.id],
        action: Ability.actions[:admin],
      ), "Actor: '#{@user}' should have a direct permission on '#{@integration}'"
    end
  end

  context ".installation_attributes_from_values" do
    test "returns empty hash if no values are provided" do
      assert_equal({}, Permissions::Service.installation_attributes_from_values(nil))
    end

    test "returns empty hash if amount of values is different from expected keys" do
      assert_equal({}, Permissions::Service.installation_attributes_from_values([1, "User"]))

      more_values_than_expected = Array.new(Permissions::Service::PERMISSION_KEYS.size + 1) { 1 }
      assert_equal({}, Permissions::Service.installation_attributes_from_values(more_values_than_expected))
    end

    test "returns a hash from permission keys and given values" do
      values = [
        42,
        "ScopedIntegrationInstallation",
        1,
        84,
        "WorkflowRun/codespaces_prebuild",
        1,
        0, # No need for a parent ID that points to an actual ability record.
        GitHub::SQL::ArelLiterals::NOW,
        GitHub::SQL::ArelLiterals::NOW,
        nil,
      ]

      hash = Permissions::Service.installation_attributes_from_values(values)

      assert_same_elements Permissions::Service::PERMISSION_KEYS, hash.keys
      assert_kind_of ActiveSupport::TimeWithZone, hash[:created_at]
      assert_kind_of ActiveSupport::TimeWithZone, hash[:updated_at]

      assert_nil hash[:expires_at]
    end

    test "keeps expires_at when is not a SQL value" do
      expiration = 1.hour.from_now

      values = [
        42,
        "ScopedIntegrationInstallation",
        1,
        84,
        "WorkflowRun/codespaces_prebuild",
        1,
        0, # No need for a parent ID that points to an actual ability record.
        GitHub::SQL::ArelLiterals::NOW,
        GitHub::SQL::ArelLiterals::NOW,
        expiration,
      ]

      hash = Permissions::Service.installation_attributes_from_values(values)
      assert_equal expiration, hash[:expires_at]
    end
  end

  def digest_from_normalized_rows(rows)
    Permissions::EntryPoint::ActorContext.digest_from_rows(
      Permissions::EntryPoint::ActorContext.normalize_rows(rows),
    )
  end
end
