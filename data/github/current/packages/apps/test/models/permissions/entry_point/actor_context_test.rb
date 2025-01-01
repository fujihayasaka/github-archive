# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

class PermissionsEntryPointActorContextTest < GitHub::TestCase
  include ApiProgrammaticGrantHelpers
  include DogstatsTestHelpers
  include HydroTestHelpers

  fixtures do
    @test_entry_point = Permissions::Service::EntryPoint.lookup(:test_case).freeze
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  def permissions_digest(permissions)
    rows = Permissions::EntryPoint::ActorContext.normalize_rows(permissions)
    Permissions::EntryPoint::ActorContext.digest_from_rows(rows)
  end

  context ".instrument" do
    test "raises with invalid metric" do
      assert_raises(KeyError) do
        Permissions::EntryPoint::ActorContext.instrument("invalid", @test_entry_point)
      end
    end

    test "stats failures to instrument with empty rows" do
      Permissions::EntryPoint::ActorContext.instrument("insert_rows_requested", @test_entry_point)
      Permissions::EntryPoint::ActorContext.instrument("insert_rows_requested", @test_entry_point, [[]])

      assert_dogstats_increment(
        2,
        Permissions::EntryPoint::ActorContext::NO_ACTOR_CONTEXT_STATS_KEY,
        tags: [
          "entry_point:test_case",
          "metric_suffix:insert_rows_requested"
        ]
      )
    end

    test "instruments from rows of hashes" do
      org = create(:organization)
      installation = make_integration_installation(target: org)
      integration = installation.integration

      hash_row = {
        actor_id: installation.id,
        actor_type: "IntegrationInstallation",
        subject_type: "Repository/metadata"
      }

      Permissions::EntryPoint::ActorContext.instrument(
        "insert_rows_requested",
        @test_entry_point,
        [hash_row]
      )

      expected_message = {
        entry_point: "test_case",
        actor_id: installation.id,
        actor_type: :ACTOR_TYPE_INTEGRATION_INSTALLATION,
        target_id: org.id,
        target_type: :TARGET_TYPE_ORGANIZATION,
        owner_id: integration.id,
        owner_name: integration.name,
        owner_type: :ACTOR_OWNER_TYPE_INTEGRATION,
        total: 1,
        subject_type_total: {
          "Repository/metadata" => 1,
        },
        write_type: :WRITE_TYPE_CREATE,
        digest: permissions_digest([hash_row]),
      }

      assert_hydro_published(expected_message, schema: "github.permissions.v0.Created")

      expected_tags = ["entry_point:test_case", "background:true"]
      assert_dogstats_distribution("permissions_actor_context.instrumentation.time", tags: expected_tags)

      expected_tags << "multiple_actors:false"
      assert_dogstats_distribution("permissions_actor_context.multiple_actor_contexts.time", tags: expected_tags)
    end

    test "instruments from legacy rows of arrays" do
      org = create(:organization)
      installation = make_integration_installation(target: org)
      integration = installation.integration

      array_row = [installation.id, "IntegrationInstallation", 0, 0, "Repository/metadata"]

      Permissions::EntryPoint::ActorContext.instrument(
        "insert_rows_requested",
        @test_entry_point,
        [array_row]
      )

      expected_message = {
        entry_point: "test_case",
        actor_id: installation.id,
        actor_type: :ACTOR_TYPE_INTEGRATION_INSTALLATION,
        target_id: org.id,
        target_type: :TARGET_TYPE_ORGANIZATION,
        owner_id: integration.id,
        owner_name: integration.name,
        owner_type: :ACTOR_OWNER_TYPE_INTEGRATION,
        total: 1,
        subject_type_total: {
          "Repository/metadata" => 1,
        },
        write_type: :WRITE_TYPE_CREATE,
        digest: permissions_digest([array_row]),
      }

      assert_hydro_published(expected_message, schema: "github.permissions.v0.Created")

      expected_tags = ["entry_point:test_case", "background:true"]
      assert_dogstats_distribution("permissions_actor_context.instrumentation.time", tags: expected_tags)
    end

    test "instruments from rows as an ActiveRecord::Relation" do
      org = create(:organization)
      installation = make_integration_installation(target: org, permissions: { "metadata" => :read })
      integration = installation.integration

      Permissions::EntryPoint::ActorContext.instrument(
        "insert_rows_requested",
        @test_entry_point,
        Permission.where(actor: installation)
      )

      expected_message = {
        entry_point: "test_case",
        actor_id: installation.id,
        actor_type: :ACTOR_TYPE_INTEGRATION_INSTALLATION,
        target_id: org.id,
        target_type: :TARGET_TYPE_ORGANIZATION,
        owner_id: integration.id,
        owner_name: integration.name,
        owner_type: :ACTOR_OWNER_TYPE_INTEGRATION,
        total: 1,
        subject_type_total: {
          "User/repositories/metadata" => 1,
        },
        write_type: :WRITE_TYPE_CREATE,
        digest: permissions_digest(Permission.where(actor: installation)),
      }

      assert_hydro_published(expected_message, schema: "github.permissions.v0.Created")

      expected_tags = ["entry_point:test_case", "background:true"]
      assert_dogstats_distribution("permissions_actor_context.instrumentation.time", tags: expected_tags)
    end

    test "instruments contexts for multiple actors" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      installation = make_integration_installation(
        target: org,
        permissions: { "metadata" => :read },
        repositories: [repo]
      )
      integration = installation.integration
      scoped_installation_1 = make_scoped_integration_installation(parent: installation, repositories: [repo])
      scoped_installation_2 = make_scoped_integration_installation(parent: installation, repositories: [repo])

      Permissions::EntryPoint::ActorContext.instrument(
        "insert_rows_requested",
        @test_entry_point,
        Permission.where(actor: [scoped_installation_1, scoped_installation_2])
      )

      expected_message = {
        entry_point: "test_case",
        actor_id: 0,
        actor_type: :ACTOR_TYPE_SCOPED_INTEGRATION_INSTALLATION,
        target_id: org.id,
        target_type: :TARGET_TYPE_ORGANIZATION,
        owner_id: integration.id,
        owner_name: integration.name,
        owner_type: :ACTOR_OWNER_TYPE_INTEGRATION,
        total: 1,
        parent_installation_id: installation.id,
        subject_type_total: {
          "Repository/metadata" => 1,
        },
        write_type: :WRITE_TYPE_CREATE,
      }

      expected_message_for_actor_1 = expected_message.merge(
        actor_id: scoped_installation_1.id,
        digest: permissions_digest(Permission.where(actor: [scoped_installation_1])),
      )
      expected_message_for_actor_2 = expected_message.merge(
        actor_id: scoped_installation_2.id,
        digest: permissions_digest(Permission.where(actor: [scoped_installation_2])),
      )

      assert_hydro_published(expected_message_for_actor_1, schema: "github.permissions.v0.Created")
      assert_hydro_published(expected_message_for_actor_2, schema: "github.permissions.v0.Created")

      expected_tags = ["entry_point:test_case", "background:true"]
      assert_dogstats_distribution("permissions_actor_context.instrumentation.time", tags: expected_tags)

      expected_tags << "multiple_actors:true"
      assert_dogstats_distribution("permissions_actor_context.multiple_actor_contexts.time", tags: expected_tags)
    end

    test "stats contexts missing owner and target" do
      hash_row = {
        actor_id: -1, # An actor that does not exist
        actor_type: "IntegrationInstallation",
        subject_type: "Repository/metadata"
      }

      Permissions::EntryPoint::ActorContext.instrument(
        "insert_rows_requested",
        @test_entry_point,
        [hash_row]
      )

      expected_message = {
        entry_point: "test_case",
        actor_id: -1,
        actor_type: :ACTOR_TYPE_INTEGRATION_INSTALLATION,
        target_id: 0,
        target_type: :TARGET_TYPE_UNKNOWN,
        owner_id: 0,
        owner_name: "",
        owner_type: :ACTOR_OWNER_TYPE_UNKNOWN,
        total: 1,
        subject_type_total: {
          "Repository/metadata" => 1,
        },
        write_type: :WRITE_TYPE_CREATE,
        digest: permissions_digest([hash_row]),
      }

      assert_hydro_published(expected_message, schema: "github.permissions.v0.Created")

      expected_tags = [
        "entry_point:test_case",
        "actor_type:IntegrationInstallation",
        "background:true",
        "reason:actor_not_found"
      ]
      assert_dogstats_increment("permissions_actor_context.incomplete_context", tags: expected_tags)
    end
  end

  context ".build_from_entry_point_only" do
    test "returns nil when entry_point has no actor present" do
      assert_nil Permissions::EntryPoint::ActorContext.build_from_entry_point_only(
        Permissions::EntryPoint::WriteType::CREATE, @test_entry_point, 1
      )
    end

    test "returns nil when entry_point has no actor_owner present" do
      actor = create(:user)
      entry_point = Permissions::Service::EntryPoint.build(
        :test_case,
        actor: actor
      )

      assert_nil Permissions::EntryPoint::ActorContext.build_from_entry_point_only(
        Permissions::EntryPoint::WriteType::CREATE, entry_point, 1
      )
    end

    test "returns context with data from the entry_point" do
      write_type = Permissions::EntryPoint::WriteType::CREATE
      actor = create(:user)
      entry_point = Permissions::Service::EntryPoint.build(
        :test_case,
        actor: actor,
        actor_owner: build(:organization)
      )

      context = Permissions::EntryPoint::ActorContext.build_from_entry_point_only(write_type, entry_point, 1)

      assert context.is_a?(Permissions::EntryPoint::ActorContext)
      assert_equal "User", T.must(context).actor_type
      assert_equal write_type, T.must(context).write_type
    end
  end

  context ".build_from_custom_entry_point" do
    test "returns nil when entry_point has no actor_owner" do
      write_type = Permissions::EntryPoint::WriteType::CREATE
      org = create(:organization)
      actor = make_integration_installation(target: org)
      entry_point = Permissions::Service::EntryPoint.build(
        :test_case,
        actor_owner: nil
      )

      rows = [
        { actor_id: actor.id, actor_type: "IntegrationInstallation", subject_type: "Repository/metadata" }
      ]

      assert_nil Permissions::EntryPoint::ActorContext.build_from_custom_entry_point(write_type, entry_point, rows)
    end

    test "returns context with data from the entry point and the rows" do
      write_type = Permissions::EntryPoint::WriteType::CREATE
      org = create(:organization)
      actor = make_integration_installation(target: org)
      entry_point = Permissions::Service::EntryPoint.build(
        :test_case,
        actor_owner: actor.integration,
      )

      rows = [
        { actor_id: actor.id, actor_type: "IntegrationInstallation", subject_type: "Repository/metadata" }
      ]

      context = Permissions::EntryPoint::ActorContext.build_from_custom_entry_point(write_type, entry_point, rows)

      assert context.is_a?(Permissions::EntryPoint::ActorContext)
      assert_equal "IntegrationInstallation", T.must(context).actor_type
      assert_equal write_type, T.must(context).write_type
    end
  end

  context ".fetch_actor_info" do
    test "returns nil with empty rows" do
      assert_equal [nil, nil], Permissions::EntryPoint::ActorContext.fetch_actor_info([])
    end

    test "extracts actor_id and actor_type from rows of hashes" do
      assert_equal [42, "IntegrationInstallation"], Permissions::EntryPoint::ActorContext.fetch_actor_info(
        [{ actor_id: 42, actor_type: "IntegrationInstallation", subject_type: "Repository/metadata" }]
      )
    end
  end

  context ".digest_from_rows" do
    test "returns nil with feature flag disabled" do
      GitHub.flipper[:permissions_entry_point_digest].disable
      assert_nil Permissions::EntryPoint::ActorContext.digest_from_rows([])
    end

    test "returns nil with empty rows" do
      GitHub.flipper[:permissions_entry_point_digest].enable
      assert_nil Permissions::EntryPoint::ActorContext.digest_from_rows([])
    end

    test "returns digest for rows of hashes" do
      GitHub.flipper[:permissions_entry_point_digest].enable
      assert_equal "94cb64de2450232f65451ff3dd92ba2de125d9799b9699d48e9ec0ad4dc1a063",
        Permissions::EntryPoint::ActorContext.digest_from_rows(
          [{ actor_id: 42, actor_type: "IntegrationInstallation", subject_type: "Repository/metadata" }]
        )
    end

    test "computes the same digest for rows of hashes in different order" do
      GitHub.flipper[:permissions_entry_point_digest].enable
      perm1 = { actor_id: 42, actor_type: "IntegrationInstallation", subject_id: 73, subject_type: "Repository/metadata" }
      perm2 = { actor_id: 42, actor_type: "IntegrationInstallation", subject_id: 99, subject_type: "Repository/metadata" }
      shuffled_perm1 = { subject_id: 73, subject_type: "Repository/metadata", actor_id: 42, actor_type: "IntegrationInstallation" }
      assert_equal \
        Permissions::EntryPoint::ActorContext.digest_from_rows([perm1, perm2]),
        Permissions::EntryPoint::ActorContext.digest_from_rows([shuffled_perm1, perm2])
    end
  end

  context ".subtotals_by_subject_type" do
    test "returns empty hash with empty rows" do
      assert_equal({}, Permissions::EntryPoint::ActorContext.subtotals_by_subject_type([]))
      assert_equal({}, Permissions::EntryPoint::ActorContext.subtotals_by_subject_type([{}]))
      assert_equal({}, Permissions::EntryPoint::ActorContext.subtotals_by_subject_type([[]]))
    end

    test "returns subtotals from rows of hashes" do
      assert_equal(
        {
          "Repository/metadata" => 1,
          "Repository/contents" => 2,
        },
        Permissions::EntryPoint::ActorContext.subtotals_by_subject_type(
          [
            {
              actor_id: 42,
              actor_type: "IntegrationInstallation",
              subject_type: "Repository/metadata"
            },
            {
              actor_id: 42,
              actor_type: "IntegrationInstallation",
              subject_type: "Repository/contents"
            },
            {
              actor_id: 42,
              actor_type: "IntegrationInstallation",
              subject_type: "Repository/contents"
            }
          ]
        )
      )
    end
  end

  context ".has_indirect_attributes?" do
    test "is false when owner is missing" do
      context = Permissions::EntryPoint::ActorContext.new(
        entry_point_tag: "test_case",
        total: 3,
        actor_id: 42,
        actor_type: "IntegrationInstallation",
        write_type: Permissions::EntryPoint::WriteType::CREATE,
        owner: nil,
        target: create(:organization)
      )

      refute_predicate context, :has_indirect_attributes?
    end

    test "is false when target is missing" do
      context = Permissions::EntryPoint::ActorContext.new(
        entry_point_tag: "test_case",
        total: 3,
        actor_id: 42,
        actor_type: "IntegrationInstallation",
        write_type: Permissions::EntryPoint::WriteType::CREATE,
        owner: create(:integration),
        target: nil
      )

      refute_predicate context, :has_indirect_attributes?
    end

    test "is true when owner and target are present" do
      context = Permissions::EntryPoint::ActorContext.new(
        entry_point_tag: "test_case",
        total: 3,
        actor_id: 42,
        actor_type: "IntegrationInstallation",
        write_type: Permissions::EntryPoint::WriteType::CREATE,
        owner: create(:integration),
        target: create(:organization)
      )

      assert_predicate context, :has_indirect_attributes?
    end
  end

  context ".normalize_rows" do
    test "returns empty array with empty rows" do
      assert_equal [], Permissions::EntryPoint::ActorContext.normalize_rows([])
    end

    test "returns array of hashes when rows are legacy array of arrays" do
      rows = [
        [42, "IntegrationInstallation", 0, 0, "Repository/metadata"]
      ]

      expected = [
        {
          actor_id: 42,
          actor_type: "IntegrationInstallation",
          subject_type: "Repository/metadata"
        }
      ]

      assert_equal expected, Permissions::EntryPoint::ActorContext.normalize_rows(rows)
    end

    test "returns array of hashes when rows are array of hashes" do
      rows = [
        "actor_id" => 42,
        "actor_type" => "IntegrationInstallation",
        "subject_type" => "Repository/metadata"
      ]

      expected = [
        {
          actor_id: 42,
          actor_type: "IntegrationInstallation",
          subject_type: "Repository/metadata"
        }
      ]

      assert_equal expected, Permissions::EntryPoint::ActorContext.normalize_rows(rows)
    end

    test "returns array of hashes when rows are a relation of Permission" do
      repo = create(:repository)
      installation = make_integration_installation(repositories: [repo], permissions: { "metadata" => :read })

      rows = Permission.where(actor: installation)
      expected = [
        {
          actor_id: installation.id,
          actor_type: "IntegrationInstallation",
          subject_type: "Repository/metadata"
        }
      ]

      assert_equal expected, Permissions::EntryPoint::ActorContext.normalize_rows(rows)
    end

    test "returns empty array when rows are a relation of non Permission records" do
      repo = create(:repository)
      installation = make_integration_installation(repositories: [repo], permissions: { "metadata" => :read })

      assert_equal [], Permissions::EntryPoint::ActorContext.normalize_rows(IntegrationInstallation.where(id: installation.id))
    end

    test "returns empty array for a legacy array of arrays with less elements than expected" do
      rows = [[42, "IntegrationInstallation", "Repository/metadata"]]
      assert_equal [], Permissions::EntryPoint::ActorContext.normalize_rows(rows)
    end
  end

  context "#to_params" do
    test "returns a hash with the correct keys" do
      org = create(:organization)
      installation = make_integration_installation(target: org)
      owner = installation.integration

      context = Permissions::EntryPoint::ActorContext.new(
        entry_point_tag: "test_case",
        total: 3,
        actor_id: installation.id,
        actor_type: "IntegrationInstallation",
        target: installation.target,
        owner: owner,
        write_type: Permissions::EntryPoint::WriteType::CREATE,
      )

      context_params = context.to_params
      expected_params = {
        actor_type: "ACTOR_TYPE_INTEGRATION_INSTALLATION",
        target_type: "TARGET_TYPE_ORGANIZATION",
        write_type: :WRITE_TYPE_CREATE,
        owner_type: "ACTOR_OWNER_TYPE_INTEGRATION",
        actor_id: installation.id,
        target_id: installation.target.id,
        total: 3,
        parent_installation_id: nil,
        owner_id: owner.id,
        owner_name: owner.name,
        entry_point: "test_case",
        subject_type_total: {},
        digest: nil,
        scope_type: :SCOPE_TYPE_UNKNOWN,
      }

      assert_same_hash(context_params, expected_params)
    end
  end

  context "#load_indirect_attributes" do
    test "makes no queries when owner and target are present" do
      context = Permissions::EntryPoint::ActorContext.new(
        entry_point_tag: "test_case",
        total: 3,
        actor_id: 42,
        actor_type: "IntegrationInstallation",
        write_type: Permissions::EntryPoint::WriteType::CREATE,
        owner: create(:integration),
        target: create(:organization)
      )

      assert_equal 0, count_queries { context.load_indirect_attributes }
    end

    test "loads owner and target when actor is an integration installation", skip_enterprise: true do
      org = create(:organization)
      installation = make_integration_installation(target: org)

      context = Permissions::EntryPoint::ActorContext.new(
        entry_point_tag: "test_case",
        total: 3,
        actor_id: installation.id,
        actor_type: installation.class.name,
        write_type: Permissions::EntryPoint::WriteType::CREATE,
      )

      primary_clusters_and_counts = {
        ApplicationRecord::Mysql1 => 0,
      }

      replica_clusters_and_counts = {
        ApplicationRecord::Mysql1 => 3,
      }

      assert_query_count_against_primary(clusters_and_counts: primary_clusters_and_counts) do
        assert_query_count_against_replicas(clusters_and_counts: replica_clusters_and_counts) do
          context.load_indirect_attributes
        end
      end

      assert_equal org, context.target
      assert_equal installation.integration, context.owner
    end

    test "loads owner and target when actor is an OAuth authorization", skip_enterprise: true do
      integration = create(:integration)
      oauth_authorization = create(:oauth_authorization, application: integration)

      context = Permissions::EntryPoint::ActorContext.new(
        entry_point_tag: "test_case",
        total: 3,
        actor_id: oauth_authorization.id,
        actor_type: oauth_authorization.class.name,
        write_type: Permissions::EntryPoint::WriteType::CREATE,
      )

      primary_clusters_and_counts = {
        ApplicationRecord::Mysql1 => 0,
      }

      replica_clusters_and_counts = {
        ApplicationRecord::Mysql1 => 3,
      }

      assert_query_count_against_primary(clusters_and_counts: primary_clusters_and_counts) do
        assert_query_count_against_replicas(clusters_and_counts: replica_clusters_and_counts) do
          context.load_indirect_attributes
        end
      end

      assert_equal oauth_authorization.user, context.target
      assert_equal integration, context.owner
    end

    test "loads owner and target when actor is an organization programmatic access grant", skip_enterprise: true do
      org = create(:organization)
      pat = create(:user_programmatic_access, :org_grants, org: org)
      grant = pat.grant

      context = Permissions::EntryPoint::ActorContext.new(
        entry_point_tag: "test_case",
        total: 3,
        actor_id: grant.id,
        actor_type: grant.class.name,
        write_type: Permissions::EntryPoint::WriteType::CREATE,
      )

      primary_clusters_and_counts = {
        ApplicationRecord::Mysql1 => 0,
        ApplicationRecord::Permissions => 0,
      }

      replica_clusters_and_counts = {
        ApplicationRecord::Mysql1 => 1,
        ApplicationRecord::Permissions => 2,
      }

      assert_query_count_against_primary(clusters_and_counts: primary_clusters_and_counts) do
        assert_query_count_against_replicas(clusters_and_counts: replica_clusters_and_counts) do
          context.load_indirect_attributes
        end
      end

      assert_equal org, context.target
      assert_equal pat, context.owner
    end

    test "loads owner and target when actor is an organization programmatic access grant request", skip_enterprise: true do
      org = create(:organization)
      member = create(:user).tap { |u| org.add_member(u) }
      pat = make_user_programmatic_access_with_grant_request(target: org, actor: member)

      context = Permissions::EntryPoint::ActorContext.new(
        entry_point_tag: "test_case",
        total: 3,
        actor_id: pat.grant_request.id,
        actor_type: pat.grant_request.class.name,
        write_type: Permissions::EntryPoint::WriteType::CREATE,
      )

      primary_clusters_and_counts = {
        ApplicationRecord::Mysql1 => 0,
        ApplicationRecord::Permissions => 0,
      }

      replica_clusters_and_counts = {
        ApplicationRecord::Mysql1 => 1,
        ApplicationRecord::Permissions => 2,
      }

      assert_query_count_against_primary(clusters_and_counts: primary_clusters_and_counts) do
        assert_query_count_against_replicas(clusters_and_counts: replica_clusters_and_counts) do
          context.load_indirect_attributes
        end
      end

      assert_equal org, context.target
      assert_equal pat, context.owner
    end

    test "loads owner and target when actor is an user programmatic access grant", skip_enterprise: true do
      user = create(:user)
      pat = create(:user_programmatic_access, :grants, owner: user)
      grant = pat.grant

      context = Permissions::EntryPoint::ActorContext.new(
        entry_point_tag: "test_case",
        total: 3,
        actor_id: grant.id,
        actor_type: grant.class.name,
        write_type: Permissions::EntryPoint::WriteType::CREATE,
      )

      primary_clusters_and_counts = {
        ApplicationRecord::Mysql1 => 0,
        ApplicationRecord::Permissions => 0,
      }

      replica_clusters_and_counts = {
        ApplicationRecord::Mysql1 => 1,
        ApplicationRecord::Permissions => 2,
      }

      assert_query_count_against_primary(clusters_and_counts: primary_clusters_and_counts) do
        assert_query_count_against_replicas(clusters_and_counts: replica_clusters_and_counts) do
          context.load_indirect_attributes
        end
      end

      assert_equal user, context.target
      assert_equal pat, context.owner
    end

    test "loads owner and target when actor is a usr programmatic access grant request", skip_enterprise: true do
      user = create(:user)
      pat = make_user_programmatic_access_with_grant_request(actor: user)
      grant_request = pat.user_programmatic_access_grant_requests.first

      context = Permissions::EntryPoint::ActorContext.new(
        entry_point_tag: "test_case",
        total: 3,
        actor_id: grant_request.id,
        actor_type: grant_request.class.name,
        write_type: Permissions::EntryPoint::WriteType::CREATE,
      )

      primary_clusters_and_counts = {
        ApplicationRecord::Mysql1 => 0,
        ApplicationRecord::Permissions => 0,
      }

      replica_clusters_and_counts = {
        ApplicationRecord::Mysql1 => 1,
        ApplicationRecord::Permissions => 2,
      }

      assert_query_count_against_primary(clusters_and_counts: primary_clusters_and_counts) do
        assert_query_count_against_replicas(clusters_and_counts: replica_clusters_and_counts) do
          context.load_indirect_attributes
        end
      end

      assert_equal user, context.target
      assert_equal pat, context.owner
    end

    test "loads owner and target when actor is an scoped integration installation", skip_enterprise: true do
      org = create(:organization)
      installation = make_integration_installation(target: org)
      integration = installation.integration
      scoped_installation = make_scoped_integration_installation(parent: installation)

      context = Permissions::EntryPoint::ActorContext.new(
        entry_point_tag: "test_case",
        total: 3,
        actor_id: scoped_installation.id,
        actor_type: scoped_installation.class.name,
        write_type: Permissions::EntryPoint::WriteType::CREATE,
      )

      primary_clusters_and_counts = {
        ApplicationRecord::Mysql1 => 0,
        ApplicationRecord::Collab => 0,
      }

      replica_clusters_and_counts = {
        ApplicationRecord::Mysql1 => 3,
        ApplicationRecord::Collab => 1,
      }

      assert_query_count_against_primary(clusters_and_counts: primary_clusters_and_counts) do
        assert_query_count_against_replicas(clusters_and_counts: replica_clusters_and_counts) do
          context.load_indirect_attributes
        end
      end

      assert_equal org, context.target
      assert_equal integration, context.owner
      assert_equal installation.id, context.to_params[:parent_installation_id]
    end

    test "loads owner and target when actor is a site scoped integration installation", skip_enterprise: true do
      GitHub.flipper[:disabled_global_apps].disable

      org = create(:organization)
      repo = create(:repository, owner: org)
      integration = create_unlimited_global_integration
      site_scoped_installation = make_site_scoped_integration_installation(
        integration: integration,
        target: org,
        repositories: [repo]
      )

      context = Permissions::EntryPoint::ActorContext.new(
        entry_point_tag: "test_case",
        total: 3,
        actor_id: site_scoped_installation.id,
        actor_type: site_scoped_installation.class.name,
        write_type: Permissions::EntryPoint::WriteType::CREATE,
      )

      primary_clusters_and_counts = {
        ApplicationRecord::Mysql1 => 0,
        ApplicationRecord::Collab => 0,
      }

      replica_clusters_and_counts = {
        ApplicationRecord::Mysql1 => 2,
        ApplicationRecord::Collab => 1,
      }

      assert_query_count_against_primary(clusters_and_counts: primary_clusters_and_counts) do
        assert_query_count_against_replicas(clusters_and_counts: replica_clusters_and_counts) do
          context.load_indirect_attributes
        end
      end

      assert_equal org, context.target
      assert_equal integration, context.owner
      assert_nil context.to_params[:parent_installation_id]
    end

    test "other actor types are ignored" do
      user = create(:user)

      context = Permissions::EntryPoint::ActorContext.new(
        entry_point_tag: "test_case",
        total: 3,
        actor_id: user.id,
        actor_type: "User",
        write_type: Permissions::EntryPoint::WriteType::CREATE,
      )

      assert_equal 0, count_queries { context.load_indirect_attributes }
      assert_nil context.target
      assert_nil context.owner
    end

    test "instruments distribution metrics", skip_enterprise: true do
      GitHub.stubs(:foreground?).returns(false)

      org = create(:organization)
      installation = make_integration_installation(target: org)

      context = Permissions::EntryPoint::ActorContext.new(
        entry_point_tag: "test_case",
        total: 3,
        actor_id: installation.id,
        actor_type: installation.class.name,
        write_type: Permissions::EntryPoint::WriteType::CREATE,
      )
      context.load_indirect_attributes

      tags = ["actor_type:IntegrationInstallation", "entry_point:test_case", "background:true"]
      assert_equal 1, GitHub.dogstats.distributions("permissions_actor_context.load_indirect_attributes.time", tags: tags).size
    end

    test "instruments actor not found", skip_enterprise: true do
      context = Permissions::EntryPoint::ActorContext.new(
        entry_point_tag: "test_case",
        total: 3,
        actor_id: -1,
        actor_type: "IntegrationInstallation",
        write_type: Permissions::EntryPoint::WriteType::CREATE,
      )
      context.load_indirect_attributes

      tags = [
        "actor_type:IntegrationInstallation",
        "entry_point:test_case",
        "background:true",
        "reason:actor_not_found"
      ]
      assert_dogstats_increment("permissions_actor_context.incomplete_context", tags: tags)
    end

    test "instruments indirect attributes not found", skip_enterprise: true do
      org = create(:organization)
      installation = make_integration_installation(target: org)

      context = Permissions::EntryPoint::ActorContext.new(
        entry_point_tag: "test_case",
        total: 3,
        actor_id: installation.id,
        actor_type: installation.class.name,
        write_type: Permissions::EntryPoint::WriteType::CREATE,
      )

      org.delete # simulate org being deleted while instrumenting

      context.load_indirect_attributes

      tags = [
        "actor_type:IntegrationInstallation",
        "entry_point:test_case",
        "background:true",
        "reason:indirect_attributes_not_found"
      ]
      assert_dogstats_increment("permissions_actor_context.incomplete_context", tags: tags)
    end

    test "does not blow up when scoped installation is missing parent installation", skip_enterprise: true do
      installation = make_integration_installation(target: create(:organization))
      scoped_installation = make_scoped_integration_installation(parent: installation)

      installation.destroy!
      # Ensure the scoped installation is still persisted. It should be destroyed
      # in the background, but the idea here is to simulate a race condition.
      assert_predicate scoped_installation.reload, :persisted?

      context = Permissions::EntryPoint::ActorContext.new(
        entry_point_tag: "test_case",
        total: 3,
        actor_id: scoped_installation.id,
        actor_type: scoped_installation.class.name,
        write_type: Permissions::EntryPoint::WriteType::DELETE,
      )

      assert_nothing_raised do
        context.load_indirect_attributes
      end

      tags = [
        "actor_type:ScopedIntegrationInstallation",
        "entry_point:test_case",
        "background:true",
        "reason:indirect_attributes_not_found"
      ]
      assert_dogstats_increment("permissions_actor_context.incomplete_context", tags: tags)
    end
  end
end
